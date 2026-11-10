#!/usr/bin/env bash
# ==============================================================================
# Script: benchmark_stress.sh
# Mục đích: Giả lập lưu lượng tải cao phục vụ Live Demo cho giảng viên.
#           Kích hoạt Rate Limiting của Nginx và tạo biểu đồ sóng trên Grafana.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

HTTP_PORT="80"
if [[ -f "$ENV_FILE" ]]; then
    HTTP_PORT=$(grep -E '^HOST_HTTP_PORT=' "$ENV_FILE" | cut -d '=' -f2 || echo "80")
fi

TARGET_URL="http://127.0.0.1:${HTTP_PORT}"
TOTAL_REQUESTS=500
CONCURRENCY=15

echo "=========================================================="
echo ">>> [BENCHMARK & STRESS TEST] Khởi tạo giả lập tải cao..."
echo "    - Target: ${TARGET_URL}"
echo "    - Tổng số requests: ${TOTAL_REQUESTS}"
echo "    - Mức độ đồng thời (Concurrency): ${CONCURRENCY}"
echo "=========================================================="

if command -v ab &>/dev/null; then
    echo "[+] Đang chạy Apache Benchmark (ab)..."
    ab -n "$TOTAL_REQUESTS" -c "$CONCURRENCY" "${TARGET_URL}/" || true
else
    echo "[!] Apache Benchmark (ab) không tìm thấy. Sử dụng vòng lặp curl đa luồng..."
    for i in $(seq 1 "$TOTAL_REQUESTS"); do
        curl -s -o /dev/null -w "%{http_code}\n" "${TARGET_URL}/" &
        if (( i % CONCURRENCY == 0 )); then
            wait
        fi
    done
    wait
fi

echo ""
echo "=========================================================="
echo ">>> [KẾT QUẢ KIỂM THỬ]:"
echo "    1. Hãy quan sát màn hình Grafana (http://<IP>:3000):"
echo "       - Host CPU & Cgroups Memory sẽ nhảy vọt."
echo "       - Endpoint Request Rate sẽ hiển thị các mã HTTP 200 và HTTP 429."
echo "    2. Kiểm tra log Nginx để thấy Rate Limiting chặn IP vượt ngưỡng:"
echo "       docker compose logs --tail=20 nginx | grep '429'"
echo "=========================================================="

