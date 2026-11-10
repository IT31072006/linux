#!/usr/bin/env bash
# ==============================================================================
# Script: auto_backup.sh
# Mục đích: Tự động sao lưu PostgreSQL, nén, hash integrity, xóa file cũ > 7 ngày,
#           gửi thông báo Telegram Bot qua cron job định kỳ.
# Tác giả: Nhóm Sinh viên Đồ án Linux & Open Source
# ==============================================================================

# cron chạy trong môi trường tối giản (minimal environment), cần thiết lập PATH rõ ràng
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

# Nạp biến môi trường từ .env
if [[ -f "$ENV_FILE" ]]; then
    # Xuất tất cả các biến từ .env
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# Cấu hình mặc định nếu biến môi trường chưa được set
DB_CONTAINER="${DB_CONTAINER:-devops_postgres}"
DB_NAME="${DB_NAME:-devops_db}"
DB_USER="${DB_USER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

START_TIME=$(date +%s)
DATE_STR=$(date +'%Y%m%d_%H%M%S')
BACKUP_FILENAME="db_backup_${DB_NAME}_${DATE_STR}.sql.gz"
BACKUP_FILEPATH="${BACKUP_DIR}/${BACKUP_FILENAME}"
CHECKSUM_FILEPATH="${BACKUP_FILEPATH}.sha256"

# Hàm gửi cảnh báo Telegram
send_telegram_notification() {
    local status="$1"
    local message="$2"

    if [[ -z "${TELEGRAM_BOT_TOKEN}" || -z "${TELEGRAM_CHAT_ID}" || "${TELEGRAM_BOT_TOKEN}" == "dummy_token_for_demo" ]]; then
        echo "[LOG] Telegram credentials chưa được cấu hình hoặc là dummy. Bỏ qua gửi tin nhắn."
        return 0
    fi

    local icon="✅"
    if [[ "$status" != "SUCCESS" ]]; then
        icon="🚨"
    fi

    local text="${icon} *[LINUX BACKUP REPORT]*%0A%0A*Trạng thái:* ${status}%0A*Server:* $(hostname)%0A*Chi tiết:*%0A${message}"

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${text}" \
        -d "parse_mode=Markdown" > /dev/null || true
}

# 1. Khởi tạo thư mục và bảo mật phân quyền Linux
mkdir -p "$BACKUP_DIR"
# Chỉ cho phép owner đọc/ghi vào thư mục backup (Defense in Depth)
chmod 700 "$BACKUP_DIR"

echo "=========================================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Bắt đầu quy trình sao lưu Database: ${DB_NAME}..."

# 2. Kiểm tra container Database có đang chạy không
if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    ERR_MSG="Container PostgreSQL '${DB_CONTAINER}' không hoạt động trên host!"
    echo "[LỖI] ${ERR_MSG}" >&2
    send_telegram_notification "FAILED" "Sao lưu thất bại: ${ERR_MSG}"
    exit 1
fi

# 3. Thực hiện pg_dump trực tiếp qua Docker exec và nén gzip tức thời qua pipeline Linux
echo "[+] Đang xuất dữ liệu từ PostgreSQL và nén gzip vào: ${BACKUP_FILENAME}..."
if docker exec -t "${DB_CONTAINER}" pg_dump -U "${DB_USER}" -d "${DB_NAME}" | gzip -9 > "${BACKUP_FILEPATH}"; then
    # Phân quyền 600: Chỉ owner có quyền đọc/ghi file backup
    chmod 600 "${BACKUP_FILEPATH}"
    
    # 4. Tính toán Checksum SHA-256 để đảm bảo tính toàn vẹn dữ liệu
    sha256sum "${BACKUP_FILEPATH}" | awk '{print $1}' > "${CHECKSUM_FILEPATH}"
    CHECKSUM_VAL=$(cat "${CHECKSUM_FILEPATH}")
    FILE_SIZE=$(du -h "${BACKUP_FILEPATH}" | cut -f1)
    
    echo "[+] Sao lưu thành công!"
    echo "    - Kích thước: ${FILE_SIZE}"
    echo "    - SHA256 Checksum: ${CHECKSUM_VAL}"
else
    ERR_MSG="Lệnh pg_dump bị gián đoạn hoặc lỗi I/O disk."
    echo "[LỖI] ${ERR_MSG}" >&2
    send_telegram_notification "FAILED" "Sao lưu thất bại: ${ERR_MSG}"
    exit 1
fi

# 5. Dọn dẹp các tệp sao lưu cũ hơn RETENTION_DAYS ngày (Data Lifecycle Management)
echo "[+] Kiểm tra và dọn dẹp các bản backup cũ hơn ${RETENTION_DAYS} ngày..."
DELETED_COUNT=0
while IFS= read -r old_file; do
    if [[ -n "$old_file" ]]; then
        rm -f "$old_file" "${old_file}.sha256"
        echo "    - Đã xóa bản sao lưu hết hạn: $(basename "$old_file")"
        DELETED_COUNT=$((DELETED_COUNT + 1))
    fi
done < <(find "$BACKUP_DIR" -type f -name "db_backup_*.sql.gz" -mtime "+${RETENTION_DAYS}")

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 6. Gửi báo cáo thành công về Telegram
SUCCESS_DETAILS="• Database: \`${DB_NAME}\`%0A• File: \`${BACKUP_FILENAME}\`%0A• Kích thước: \`${FILE_SIZE}\`%0A• SHA256: \`${CHECKSUM_VAL:0:16}...\`%0A• Đã dọn dẹp: \`${DELETED_COUNT} file cũ\`%0A• Thời gian thực thi: \`${DURATION}s\`"
send_telegram_notification "SUCCESS" "${SUCCESS_DETAILS}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Toàn bộ quy trình sao lưu hoàn tất trong ${DURATION} giây."
echo "=========================================================="

