# Đồ Án Môn Học: Linux & Phần Mềm Nguồn Mở
## Đề Tài: "Configure and Deploy DevOps Services in Linux"
**Hệ điều hành mục tiêu:** Ubuntu Server 22.04 / 24.04 LTS  
**Kiến trúc:** Containerized GitOps & CI/CD Pipeline (Gitea Actions, Docker Compose, Nginx, PostgreSQL, Prometheus, Grafana, Bash Automation)

---

## 1. Cấu Trúc Thư Mục Dự Án
```text
DoAnCuoiKi/
├── .gitea/
│   └── workflows/
│       └── deploy.yaml                # Pipeline CI/CD tự động (Lint, Test, Build, Deploy, Rollback)
├── frontend/
│   └── index.html                     # Web Dashboard & DevOps Control Center (Tailwind + Alpine.js)
├── app/
│   ├── main.py                        # FastAPI Backend tích hợp Prometheus metrics & DB checks
│   ├── requirements.txt               # Thư viện Python phụ thuộc
│   ├── Dockerfile                     # Multi-stage Dockerfile chạy non-root user
│   └── tests/
│       └── test_main.py               # Unit Test Suite (pytest)
├── nginx/
│   ├── nginx.conf                     # Cấu hình lõi (epoll, rate limit zone, security headers)
│   └── conf.d/
│       ├── 00-upstream.conf           # Dynamic Upstream chuyển mạch Blue <-> Green
│       └── app.conf                   # Reverse proxy, load balancing least_conn, timeouts
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml             # Cấu hình scrape Node Exporter, cAdvisor, FastAPI
│   ├── loki/
│   │   └── loki-config.yml            # Centralized Logging TSDB Engine (< 200MB RAM)
│   ├── promtail/
│   │   └── promtail-config.yml        # Nginx JSON log parser & Docker socket log collector
│   └── grafana/
│       └── provisioning/              # Auto-provisioning Datasource (Prometheus, Loki) & Dashboard
├── logs/
│   └── nginx/                         # Thư mục lưu access.log (JSON) và error.log của Nginx
├── scripts/
│   ├── setup_server.sh                # Hardening OS, UFW, Kernel sysctl, Docker, Crontab
│   ├── service_manager.sh             # CLI quản trị runtime (đổi port, switch env, reload SIGHUP)
│   ├── blue_green_deploy.sh           # Triển khai Blue-Green Zero-Downtime High Availability
│   ├── auto_backup.sh                 # Cronjob dump PostgreSQL, nén gzip, hash sha256, báo Telegram
│   └── healthcheck_rollback.sh        # Post-deploy HTTP probe & auto rollback container
├── docker-compose.yml                 # Orchestration 10 services (DB, Blue, Green, Nginx, Prometheus, Grafana, Loki, Promtail, Node-Exp, cAdvisor)
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
- **Kiểm tra Healthcheck & Rollback:** `./scripts/healthcheck_rollback.sh`

---

## 4. Truy Cập Dịch Vụ
- **Web Dashboard & DevOps Control Center:** `http://<SERVER_IP>/`
- **Swagger API Interactive Docs:** `http://<SERVER_IP>/docs`
- **Healthcheck Probe:** `http://<SERVER_IP>/health`
- **Prometheus UI:** `http://<SERVER_IP>:9090`
- **Loki Log Gateway:** `http://<SERVER_IP>:3100/ready`
- **Grafana Dashboard (Metrics & Logs):** `http://<SERVER_IP>:3000` (User: `admin` / Pass: `admin_devops_password`)

