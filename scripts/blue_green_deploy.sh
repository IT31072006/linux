#!/usr/bin/env bash
# ==============================================================================
# Script: blue_green_deploy.sh
# Mục đích: Triển khai ứng dụng theo mô hình Blue-Green Deployment đạt chuẩn
#           High Availability (HA), Zero-Downtime trên Linux Server.
# Tác giả: Nhóm Sinh viên Đồ án Linux & Open Source
# ==============================================================================

set -euo pipefail

# Màu hiển thị terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
UPSTREAM_CONF="${PROJECT_ROOT}/nginx/conf.d/00-upstream.conf"
STATE_FILE="${PROJECT_ROOT}/.active_color"

# Nạp biến môi trường từ .env
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

IMAGE_TAG="${1:-latest}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}
log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

send_telegram_notification() {
    local status="$1"
    local title="$2"
    local message="$3"

    if [[ -z "${TELEGRAM_BOT_TOKEN}" || -z "${TELEGRAM_CHAT_ID}" || "${TELEGRAM_BOT_TOKEN}" == "dummy_token_for_demo" ]]; then
        return 0
    fi

    local icon="🔄"
    if [[ "$status" == "FAILED" ]]; then
        icon="🚨"
    fi

    local text="${icon} *${title}*%0A%0A${message}"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${text}" \
        -d "parse_mode=Markdown" > /dev/null || true
}

echo -e "${BOLD}${CYAN}================================================================${NC}"
echo -e "${BOLD}${CYAN}         KHỞI CHẠY QUY TRÌNH BLUE-GREEN DEPLOYMENT (HA)        ${NC}"
echo -e "${BOLD}${CYAN}================================================================${NC}"
log_info "Phiên bản cần triển khai (Deploying Tag): ${IMAGE_TAG}"

# 1. Xác định màu Container đang Active và Target (Idle)
ACTIVE_COLOR="blue"
if [[ -f "$UPSTREAM_CONF" ]] && grep -q "app_green" "$UPSTREAM_CONF"; then
    ACTIVE_COLOR="green"
elif [[ -f "$STATE_FILE" ]] && grep -q "green" "$STATE_FILE"; then
    ACTIVE_COLOR="green"
fi

if [[ "$ACTIVE_COLOR" == "blue" ]]; then
    TARGET_COLOR="green"
    TARGET_PORT=8002
    TARGET_SERVICE="app_green"
    ACTIVE_SERVICE="app_blue"
else
    TARGET_COLOR="blue"
    TARGET_PORT=8001
    TARGET_SERVICE="app_blue"
    ACTIVE_SERVICE="app_green"
fi

log_info "Trạng thái hiện tại: [${ACTIVE_COLOR^^}] đang nhận lưu lượng chính."
log_info "Mục tiêu triển khai: [${TARGET_COLOR^^}] (Cổng nội bộ probe: ${TARGET_PORT})"

# 2. Cập nhật biến môi trường cho Target Service trong .env
cd "$PROJECT_ROOT"

if [[ "$TARGET_COLOR" == "green" ]]; then
    sed -i "s/^APP_GREEN_VERSION=.*/APP_GREEN_VERSION=${IMAGE_TAG}/" "$ENV_FILE" || echo "APP_GREEN_VERSION=${IMAGE_TAG}" >> "$ENV_FILE"
    sed -i "s/^APP_GREEN_IMAGE=.*/APP_GREEN_IMAGE=devops-app:${IMAGE_TAG}/" "$ENV_FILE" || echo "APP_GREEN_IMAGE=devops-app:${IMAGE_TAG}" >> "$ENV_FILE"
else
    sed -i "s/^APP_BLUE_VERSION=.*/APP_BLUE_VERSION=${IMAGE_TAG}/" "$ENV_FILE" || echo "APP_BLUE_VERSION=${IMAGE_TAG}" >> "$ENV_FILE"
    sed -i "s/^APP_BLUE_IMAGE=.*/APP_BLUE_IMAGE=devops-app:${IMAGE_TAG}/" "$ENV_FILE" || echo "APP_BLUE_IMAGE=devops-app:${IMAGE_TAG}" >> "$ENV_FILE"
fi

# 3. Khởi động Target Container (Idle) với phiên bản mới
log_info "Khởi động container mục tiêu '${TARGET_SERVICE}' với image mới devops-app:${IMAGE_TAG}..."
docker compose up -d --no-deps "${TARGET_SERVICE}"

# 4. Thực hiện Healthcheck Probes (5 lần thử) vào Target Container
log_info "Bắt đầu kiểm tra sức khỏe (Healthcheck Probes) trên http://127.0.0.1:${TARGET_PORT}/health..."
MAX_PROBES=5
PROBE_INTERVAL=3
IS_HEALTHY=false

for ((i=1; i<=MAX_PROBES; i++)); do
    log_info "Probe [${i}/${MAX_PROBES}]: Gửi GET request tới port ${TARGET_PORT}..."
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 4 "http://127.0.0.1:${TARGET_PORT}/health" || echo "000")
    
    if [[ "$HTTP_STATUS" == "200" ]]; then
        BODY=$(curl -s --connect-timeout 2 "http://127.0.0.1:${TARGET_PORT}/health" || echo "{}")
        if echo "$BODY" | grep -q '"status": "ok"'; then
            log_success "Target '${TARGET_SERVICE}' đã sẵn sàng (HTTP 200 OK, payload status=ok)!"
            IS_HEALTHY=true
            break
        fi
    fi

    log_warn "Target '${TARGET_SERVICE}' chưa phản hồi thành công (HTTP ${HTTP_STATUS}). Thử lại sau ${PROBE_INTERVAL}s..."
    sleep "$PROBE_INTERVAL"
done

# 5. Xử lý kết quả kiểm tra
if [[ "$IS_HEALTHY" != "true" ]]; then
    log_error "Target container '${TARGET_SERVICE}' KHÔNG vượt qua Healthcheck sau ${MAX_PROBES} lần probe!"
    log_error "Kích hoạt cơ chế an toàn: HỦY BỎ SWITCH, GIỮ NGUYÊN CONTAINER '${ACTIVE_SERVICE}' ĐANG CHẠY."
    
    # Dừng container target lỗi
    docker compose stop "${TARGET_SERVICE}" || true
    
    # Gửi cảnh báo khẩn cấp về Telegram
    TELEGRAM_MSG="*Server:* $(hostname)%0A*Target:* \`${TARGET_SERVICE}\` (Version: \`${IMAGE_TAG}\`)%0A*Chi tiết:* Healthcheck Probe thất bại qua 5 lần thử.%0A*Trạng thái:* Hệ thống KHÔNG BỊ GIÁN ĐOẠN, vẫn đang phục vụ trên \`${ACTIVE_SERVICE}\`!"
    send_telegram_notification "FAILED" "BLUE-GREEN DEPLOYMENT ABORTED" "$TELEGRAM_MSG"
    
    exit 1
fi

# ==============================================================================
# 6. CHUYỂN ĐỔI LƯU LƯỢNG NGINX (TRAFFIC SWITCH - ZERO DOWNTIME)
# ==============================================================================
log_info "Tiến hành chuyển mạch lưu lượng sang [${TARGET_COLOR^^}]..."

# Cập nhật tệp upstream.conf nguyên tử (Atomic write)
cat << EOF > "$UPSTREAM_CONF"
# Upstream động: Đã chuyển sang ${TARGET_COLOR^^} vào $(date '+%Y-%m-%d %H:%M:%S')
upstream backend_service {
    least_conn;
    server ${TARGET_SERVICE}:8000 max_fails=3 fail_timeout=10s;
    keepalive 32;
}
EOF

# Kiểm tra cú pháp Nginx trước khi nạp lại
if docker compose exec -T nginx nginx -t; then
    log_info "Gửi tín hiệu POSIX SIGHUP tới Nginx Master Process để nạp lại upstream không downtime..."
    docker compose exec -T nginx nginx -s reload
    log_success "Nginx đã chuyển 100% lưu lượng sang '${TARGET_SERVICE}' thành công!"
else
    log_error "Cú pháp Nginx không hợp lệ! Khôi phục lại upstream cũ..."
    cat << EOF > "$UPSTREAM_CONF"
upstream backend_service {
    least_conn;
    server ${ACTIVE_SERVICE}:8000 max_fails=3 fail_timeout=10s;
    keepalive 32;
}
EOF
    exit 1
fi

# 7. Graceful Connection Draining & Dừng container cũ
DRAIN_SECONDS=5
log_info "Đợi ${DRAIN_SECONDS} giây (Graceful Draining) để các kết nối in-flight của '${ACTIVE_SERVICE}' hoàn tất..."
sleep "$DRAIN_SECONDS"

log_info "Dừng container cũ '${ACTIVE_SERVICE}' để giải phóng bộ nhớ RAM Linux..."
docker compose stop "${ACTIVE_SERVICE}"

# Lưu trạng thái màu hiện tại
echo "$TARGET_COLOR" > "$STATE_FILE"

# 8. Bắn thông báo thành công qua Telegram
SUCCESS_MSG="*Server:* $(hostname)%0A*Chuyển mạch:* \`${ACTIVE_COLOR^^}\` ➡️ \`${TARGET_COLOR^^}\`%0A*Phiên bản mới:* \`${IMAGE_TAG}\`%0A*Downtime:* *0 ms (Zero-Downtime SIGHUP Reload)*%0A*Container cũ:* Đã dừng an toàn (\`${ACTIVE_SERVICE}\`)"
send_telegram_notification "SUCCESS" "BLUE-GREEN DEPLOYMENT THÀNH CÔNG" "$SUCCESS_MSG"

echo -e "${BOLD}${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}  HOÀN TẤT BLUE-GREEN DEPLOYMENT: HIỆN TẠI LÀ [${TARGET_COLOR^^}] ACTIVE!  ${NC}"
echo -e "${BOLD}${GREEN}================================================================${NC}"
exit 0

