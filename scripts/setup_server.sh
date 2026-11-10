#!/usr/bin/env bash
# ==============================================================================
# Script: setup_server.sh
# Mục đích: Bootstrap và làm cứng bảo mật (Hardening) hệ điều hành Ubuntu Server
#           22.04 / 24.04 LTS cho hạ tầng DevOps
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "[!] Script này yêu cầu quyền root (hãy chạy với: sudo bash $0)" >&2
   exit 1
fi

echo "=========================================================="
echo ">>> [STEP 1] Cập nhật gói hệ thống Ubuntu..."
apt-get update -y && apt-get upgrade -y
apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    ufw \
    fail2ban \
    htop \
    iotop \
    ca-certificates \
    gnupg \
    lsb-release

echo "=========================================================="
echo ">>> [STEP 2] Cài đặt Docker Engine & Docker Compose Plugin..."
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl start docker
fi

echo "=========================================================="
echo ">>> [STEP 3] Cấu hình Firewall (UFW) tối ưu bảo mật..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH Port'
ufw allow 80/tcp comment 'HTTP Nginx'
ufw allow 443/tcp comment 'HTTPS Nginx'
ufw allow 3000/tcp comment 'Grafana Dashboard'
# Kích hoạt UFW tự động không cần prompt
echo "y" | ufw enable || true

echo "=========================================================="
echo ">>> [STEP 4] Thiết lập Crontab tự động chạy auto_backup.sh lúc 02:00 hàng ngày..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/auto_backup.sh"
chmod +x "$BACKUP_SCRIPT"

# Kiểm tra xem cron job đã có trong crontab chưa
CRON_JOB="0 2 * * * ${BACKUP_SCRIPT} >> /var/log/devops_backup.log 2>&1"
( crontab -l 2>/dev/null | grep -Fv "${BACKUP_SCRIPT}" ; echo "${CRON_JOB}" ) | crontab -

echo "=========================================================="
echo ">>> [STEP 5] Tối ưu hóa tham số Linux Kernel (/etc/sysctl.d/99-devops.conf)..."
cat << 'EOF' > /etc/sysctl.d/99-devops.conf
# Tối ưu hóa socket và TCP buffer cho Reverse Proxy
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
# Tối ưu bộ nhớ ảo và giám sát file (cho Docker & Prometheus)
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
EOF
sysctl --system > /dev/null

echo "=========================================================="
echo ">>> HOÀN TẤT CẤU HÌNH SERVER! Hệ điều hành đã sẵn sàng chạy CI/CD & Docker Services."
echo "=========================================================="

