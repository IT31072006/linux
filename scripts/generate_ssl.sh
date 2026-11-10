#!/usr/bin/env bash
# ==============================================================================
# Script: generate_ssl.sh
# Mục đích: Tạo chứng chỉ SSL/TLS tự ký (Self-signed) chuẩn OpenSSL X.509
#           cho Nginx Reverse Proxy phục vụ demo HTTPS an toàn trên Linux.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSL_DIR="${SCRIPT_DIR}/../nginx/ssl"

mkdir -p "$SSL_DIR"

KEY_FILE="${SSL_DIR}/selfsigned.key"
CERT_FILE="${SSL_DIR}/selfsigned.crt"

echo "=========================================================="
echo ">>> [OPENSSL] Khởi tạo cặp khóa RSA 2048-bit và chứng chỉ X.509..."
echo "=========================================================="

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/C=VN/ST=HoChiMinh/L=HoChiMinh/O=DevOpsTeam/OU=LinuxCourse/CN=localhost"

# Bảo mật quyền truy cập private key: chỉ owner được đọc
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

echo "[+] Đã tạo thành công chứng chỉ SSL tự ký:"
echo "    - Private Key: ${KEY_FILE}"
echo "    - Certificate: ${CERT_FILE}"
echo "=========================================================="

