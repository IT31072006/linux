# Đồ Án Môn Học: Linux & Phần Mềm Nguồn Mở
## Đề Tài: "Configure and Deploy DevOps Services in Linux"
**Hệ điều hành mục tiêu:** Ubuntu Server 22.04 / 24.04 LTS  
**Trọng tâm kỹ thuật:** Tập trung chuyên sâu vào **2 dịch vụ mã nguồn mở cốt lõi** trên Linux:
1. **Nginx Gateway & High Availability:** Reverse Proxy, Rate Limiting (chống DoS), và triển khai không gián đoạn (**Blue-Green Deployment** qua tín hiệu `POSIX SIGHUP`).
2. **Prometheus & Grafana Monitoring:** Thu thập chỉ số hệ điều hành Linux từ `/proc`, `/sys` (`Node Exporter`) và trực quan hóa hiệu năng Request Rate / Latency theo thời gian thực.

*(Kèm ứng dụng mẫu FastAPI + PostgreSQL và bộ Bash Scripts tự động hóa quản trị Linux).*

---

## 1. Cấu Trúc Thư Mục Dự Án
```text
DoAnCuoiKi/
├── .gitea/workflows/deploy.yaml       # Pipeline CI/CD tự động (Gitea Actions)
├── .github/workflows/deploy.yaml      # Pipeline CI/CD tự động (GitHub Actions)
├── frontend/
│   └── index.html                     # Web Dashboard & DevOps Control Center
├── app/
│   ├── main.py                        # Sample FastAPI Backend tích hợp Prometheus metrics
│   ├── requirements.txt               # Thư viện Python phụ thuộc
│   ├── Dockerfile                     # Multi-stage Dockerfile chạy non-root user (UID 10001)
│   └── tests/test_main.py             # Unit Test Suite (pytest)
├── nginx/
│   ├── nginx.conf                     # Cấu hình lõi Nginx (epoll, rate limit zone, JSON log)
│   └── conf.d/
│       ├── 00-upstream.conf           # Dynamic Upstream chuyển mạch Blue <-> Green
│       └── app.conf                   # Reverse proxy, load balancing least_conn, OWASP headers
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml             # Cấu hình scrape Node Exporter & FastAPI metrics
│   └── grafana/
│       └── provisioning/              # Auto-provisioning Datasource (Prometheus) & Dashboard
├── logs/
│   └── nginx/                         # Thư mục lưu access.log và error.log của Nginx
├── scripts/
│   ├── setup_server.sh                # Hardening OS, UFW, Kernel sysctl, Docker, Crontab
│   ├── service_manager.sh             # CLI quản trị runtime (đổi port, switch env, reload SIGHUP)
│   ├── blue_green_deploy.sh           # Triển khai Blue-Green Zero-Downtime High Availability
│   ├── auto_backup.sh                 # Cronjob dump PostgreSQL, nén gzip, hash sha256, báo Telegram
│   ├── healthcheck_rollback.sh        # Post-deploy HTTP probe & auto rollback container
│   ├── benchmark_stress.sh            # Tạo tải giả lập demo Rate Limiting & Grafana Spike
│   └── generate_ssl.sh                # Tạo chứng chỉ SSL/TLS self-signed với OpenSSL
├── docker-compose.yml                 # Orchestration 7 containers gọn nhẹ với network isolation
├── .env.example                       # File mẫu biến môi trường
└── README.md
```

---

## 2. Hướng Dẫn Cài Đặt Nhanh

### Bước 1: Khởi tạo máy chủ Ubuntu Server (Chạy 1 lần duy nhất)
```bash
sudo bash scripts/setup_server.sh
```

### Bước 2: Khởi động hệ thống
```bash
cp .env.example .env
./scripts/service_manager.sh start
```

### Bước 3: Kiểm tra trạng thái
```bash
./scripts/service_manager.sh status
```

---

## 3. Các Công Cụ Quản Trị Hệ Thống (Custom Bash Scripts)
- **Menu Quản trị:** `./scripts/service_manager.sh` (chạy interactive CLI hoặc truyền tham số)
- **Chuyển mạch Blue-Green:** `./scripts/blue_green_deploy.sh [tag]` hoặc `./scripts/service_manager.sh deploy-bg`
- **Đổi HTTP Port:** `./scripts/service_manager.sh set-port 8080`
- **Chuyển môi trường:** `./scripts/service_manager.sh switch-env staging`
- **Reload Nginx không gián đoạn:** `./scripts/service_manager.sh reload`
- **Sao lưu DB thủ công:** `./scripts/auto_backup.sh`
- **Giả lập Stress Test (Demo):** `./scripts/benchmark_stress.sh`
- **Kiểm tra Healthcheck & Rollback:** `./scripts/healthcheck_rollback.sh`

---

## 4. Truy Cập Dịch Vụ
- **Web Dashboard & DevOps Control Center:** `http://<SERVER_IP>/` (hoặc `:8088` nếu cấu hình `HOST_HTTP_PORT=8088`)
- **Swagger API Interactive Docs:** `http://<SERVER_IP>/docs`
- **Healthcheck Probe:** `http://<SERVER_IP>/health`
- **Prometheus UI:** `http://<SERVER_IP>:9090`
- **Grafana Dashboard (Host OS & Nginx/API Metrics):** `http://<SERVER_IP>:3000` (User: `admin` / Pass: `admin_devops_password`)
