#!/usr/bin/env bash
# ==============================================================================
# Script: healthcheck_rollback.sh
# Mục đích: Thực hiện probe kiểm tra endpoint sau deploy. Nếu lỗi quá ngưỡng,
#           tự động rollback container về phiên bản stable trước đó.
# Tác giả: Nhóm Sinh viên Đồ án Linux & Open Source
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
STABLE_TAG_FILE="${PROJECT_ROOT}/.last_stable_tag"

# Nạp biến môi trường
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

HTTP_PORT="${HOST_HTTP_PORT:-80}"
HEALTH_URL="http://127.0.0.1:${HTTP_PORT}/health"
MAX_RETRIES=3
RETRY_INTERVAL_SECONDS=4
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

NEW_TAG="${APP_VERSION:-unknown}"

# Khởi tạo stable tag ban đầu nếu chưa có
if [[ ! -f "$STABLE_TAG_FILE" ]]; then
    echo "devops-app:1.0.0" > "$STABLE_TAG_FILE"
fi

LAST_STABLE_IMAGE=$(cat "$STABLE_TAG_FILE")

send_telegram_alert() {
    local title="$1"
    local message="$2"

    if [[ -z "${TELEGRAM_BOT_TOKEN}" || -z "${TELEGRAM_CHAT_ID}" || "${TELEGRAM_BOT_TOKEN}" == "dummy_token_for_demo" ]]; then
        return 0
    fi

    local text="🚨 *${title}*%0A%0A${message}"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${text}" \
        -d "parse_mode=Markdown" > /dev/null || true
}

echo "=========================================================="
echo "[+] Bắt đầu Post-Deployment Health Check Probe..."
echo "    - Target URL: ${HEALTH_URL}"
echo "    - Deploying Tag: ${NEW_TAG}"
echo "    - Fallback Stable Image: ${LAST_STABLE_IMAGE}"
echo "=========================================================="

ATTEMPT=1
IS_HEALTHY=false

while [ "$ATTEMPT" -le "$MAX_RETRIES" ]; do
    echo "[Probe ${ATTEMPT}/${MAX_RETRIES}] Gửi HTTP GET request tới ${HEALTH_URL}..."
    
    # Sử dụng curl lấy HTTP status code và response body
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "$HEALTH_URL" || echo "000")
    
    if [ "$HTTP_CODE" -eq 200 ]; then
        echo "[+] Nhận mã HTTP 200 OK. Kiểm tra tính toàn vẹn payload JSON..."
        RESPONSE_BODY=$(curl -s --connect-timeout 3 "$HEALTH_URL")
        
        if echo "$RESPONSE_BODY" | grep -q '"status": "ok"'; then
            echo "[+] Dịch vụ phản hồi hợp lệ: ${RESPONSE_BODY}"
            IS_HEALTHY=true
            break
        else
            echo "[-] Payload không đúng định dạng mong đợi: ${RESPONSE_BODY}"
        fi
    else
        echo "[-] Request thất bại với HTTP status: ${HTTP_CODE}"
    fi

    if [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; then
        echo "[!] Đợi ${RETRY_INTERVAL_SECONDS} giây trước khi probe lại..."
        sleep "$RETRY_INTERVAL_SECONDS"
    fi
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$IS_HEALTHY" = true ]; then
    echo "=========================================================="
    echo ">>> [DEPLOYS SUCCESS] Ứng dụng đã sẵn sàng phục vụ lưu lượng!"
    # Cập nhật image vừa deploy thành stable image mới
    echo "devops-app:${NEW_TAG}" > "$STABLE_TAG_FILE"
    echo "=========================================================="
    exit 0
fi

# ==============================================================================
# QUY TRÌNH TỰ ĐỘNG ROLLBACK NẾU HEALTHCHECK THẤT BẠI
# ==============================================================================
echo "=========================================================="
echo ">>> [CRITICAL] Ứng dụng không vượt qua health-check sau ${MAX_RETRIES} lần thử!"
echo ">>> [ACTION] Kích hoạt quy trình TỰ ĐỘNG ROLLBACK ngay lập tức..."
echo "=========================================================="

# 1. Thu thập log cuối của container lỗi để phục vụ điều tra (Post-mortem)
ERROR_LOGS=$(docker compose -f "${PROJECT_ROOT}/docker-compose.yml" logs --tail=20 app || echo "Không lấy được log")

# 2. Khôi phục image stable cũ vào .env
sed -i "s|^APP_CONTAINER_IMAGE=.*|APP_CONTAINER_IMAGE=${LAST_STABLE_IMAGE}|" "$ENV_FILE"

# 3. Re-deploy container với image stable
echo "[+] Đang rollback container 'app' về: ${LAST_STABLE_IMAGE}..."
cd "$PROJECT_ROOT"
docker compose up -d --no-deps app
docker compose exec -T nginx nginx -s reload || true

# 4. Gửi tin nhắn khẩn cấp về Telegram
ALERT_MSG="*Hệ thống:* $(hostname)%0A*Lỗi:* Healthcheck HTTP Probe thất bại 3 lần%0A*Phiên bản lỗi:* \`${NEW_TAG}\`%0A*Hành động:* Đã tự động rollback về \`${LAST_STABLE_IMAGE}\` an toàn!%0A%0A*Log lỗi gần nhất:*%0A\`\`\`%0A$(echo "$ERROR_LOGS" | tail -n 5)%0A\`\`\`"
send_telegram_alert "AUTO-ROLLBACK TRIGGERED" "$ALERT_MSG"

echo "[+] Rollback hoàn tất. Hệ thống đã khôi phục trạng thái ổn định."
# Trả về exit code 1 để thông báo CI pipeline biết lần deploy này thất bại
exit 1

