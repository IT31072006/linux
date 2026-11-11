#!/usr/bin/env bash
# ==============================================================================
# Script: service_manager.sh
# Mục đích: Quản trị runtime, đổi port, switch môi trường, reload zero-downtime
# Tác giả: Nhóm Sinh viên Đồ án Linux & Open Source
# ==============================================================================

set -euo pipefail

# Màu ANSI hiển thị trực quan trên terminal Linux
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Thư mục gốc chứa docker-compose.yml và .env
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

# Bắt tín hiệu Ctrl+C để dọn dẹp terminal an toàn
trap 'echo -e "\n${YELLOW}[!] Đã hủy thao tác.${NC}"; exit 130' SIGINT SIGTERM

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

# Kiểm tra dependency cần thiết trên Linux
check_dependencies() {
    for cmd in docker sed awk grep; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Công cụ bắt buộc '$cmd' chưa được cài đặt trên hệ điều hành."
            exit 1
        fi
    done

    if [[ ! -f "$ENV_FILE" ]]; then
        log_warn "Tệp .env chưa tồn tại. Đang tạo từ .env.example..."
        cp "${PROJECT_ROOT}/.env.example" "$ENV_FILE"
    fi
}

# 1. Hiển thị trạng thái chi tiết của toàn bộ hệ thống
show_status() {
    log_info "Trạng thái các container dịch vụ:"
    cd "$PROJECT_ROOT"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

    echo ""
    local active_color="blue"
    if [[ -f "${PROJECT_ROOT}/nginx/conf.d/00-upstream.conf" ]] && grep -q "app_green" "${PROJECT_ROOT}/nginx/conf.d/00-upstream.conf"; then
        active_color="green"
    fi
    log_info "Mô hình Blue-Green Deployment: Node đang nhận Traffic = [${active_color^^}]"

    echo ""
    log_info "Tài nguyên CPU / RAM tiêu thụ theo thời gian thực (Cgroups):"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

    echo ""
    log_info "Cấu hình môi trường hiện tại (.env):"
    grep -E '^(APP_ENV|APP_VERSION|HOST_HTTP_PORT|DB_NAME)=' "$ENV_FILE" || true

    echo ""
    log_info "Kiểm tra socket đang lắng nghe trên Host OS (Port binding):"
    local current_port
    current_port=$(grep -E '^HOST_HTTP_PORT=' "$ENV_FILE" | cut -d '=' -f2 || echo "80")
    if command -v ss &>/dev/null; then
        ss -tulpn | grep ":${current_port} " || echo "Port ${current_port} chưa được socket nào mở."
    fi
}

# 2. Thay đổi Port của Nginx Reverse Proxy
set_port() {
    local new_port="${1:-}"

    if [[ -z "$new_port" ]]; then
        read -rp "Nhập Port HTTP mới mong muốn (1024 - 65535 khuyến nghị cho non-root): " new_port
    fi

    # Kiểm tra tính hợp lệ bằng Regex số nguyên
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        log_error "Port '$new_port' không hợp lệ! Giá trị phải từ 1 đến 65535."
        return 1
    fi

    # Kiểm tra xem port có đang bị chiếm dụng bởi tiến trình Linux khác không
    if command -v ss &>/dev/null; then
        if ss -tulpn | grep -q ":${new_port} "; then
            log_warn "Cảnh báo: Port $new_port dường như đang được một tiến trình khác lắng nghe."
            read -rp "Bạn có chắc chắn muốn tiếp tục gán port này? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log_info "Hủy bỏ đổi port."
                return 0
            fi
        fi
    fi

    log_info "Đang cập nhật HOST_HTTP_PORT thành $new_port trong $ENV_FILE..."
    if grep -q "^HOST_HTTP_PORT=" "$ENV_FILE"; then
        sed -i "s/^HOST_HTTP_PORT=.*/HOST_HTTP_PORT=${new_port}/" "$ENV_FILE"
    else
        echo "HOST_HTTP_PORT=${new_port}" >> "$ENV_FILE"
    fi

    log_info "Áp dụng port mới cho Nginx container..."
    cd "$PROJECT_ROOT"
    docker compose up -d --no-deps nginx

    log_success "Đã chuyển đổi HTTP Port thành công: http://localhost:${new_port}"
}

# 3. Chuyển đổi giữa môi trường Staging và Production
switch_environment() {
    local target_env="${1:-}"

    if [[ -z "$target_env" ]]; then
        echo -e "\nChọn môi trường cần chuyển đổi:"
        echo "1) staging     (Debug log, tối ưu test)"
        echo "2) production  (Bảo mật cao, log JSON, tối ưu hiệu năng)"
        read -rp "Lựa chọn [1-2]: " env_choice
        case "$env_choice" in
            1) target_env="staging" ;;
            2) target_env="production" ;;
            *) log_error "Lựa chọn không hợp lệ"; return 1 ;;
        esac
    fi

    if [[ "$target_env" != "staging" && "$target_env" != "production" ]]; then
        log_error "Môi trường phải là 'staging' hoặc 'production'."
        return 1
    fi

    log_info "Đang chuyển cấu hình APP_ENV sang: ${target_env}..."
    if grep -q "^APP_ENV=" "$ENV_FILE"; then
        sed -i "s/^APP_ENV=.*/APP_ENV=${target_env}/" "$ENV_FILE"
    else
        echo "APP_ENV=${target_env}" >> "$ENV_FILE"
    fi

    cd "$PROJECT_ROOT"
    log_info "Cập nhật runtime FastAPI container..."
    docker compose up -d --no-deps app

    log_success "Chuyển môi trường sang [${target_env}] hoàn tất!"
}

# 4. Nginx Zero-Downtime Reload (Sử dụng tín hiệu SIGHUP của Linux)
reload_nginx() {
    log_info "Gửi tín hiệu SIGHUP (reload) đến Nginx Master Process..."
    cd "$PROJECT_ROOT"
    if docker compose exec -T nginx nginx -t; then
        docker compose exec -T nginx nginx -s reload
        log_success "Nginx đã nạp lại cấu hình mới mà không ngắt kết nối client đang mở (Zero-Downtime Reload)!"
    else
        log_error "Kiểm tra cú pháp Nginx cấu hình thất bại! Giữ nguyên cấu hình cũ để không gián đoạn dịch vụ."
        return 1
    fi
}

# 5. Khởi động / Khởi động lại dịch vụ
start_services() {
    log_info "Khởi động toàn bộ stack DevOps..."
    cd "$PROJECT_ROOT"
    docker compose up -d
    log_success "Dịch vụ đã được kích hoạt!"
}

stop_services() {
    log_info "Dừng toàn bộ stack DevOps gracefully..."
    cd "$PROJECT_ROOT"
    docker compose stop
    log_success "Tất cả container đã dừng an toàn."
}

# 6. Xem logs trực tiếp
view_logs() {
    local service="${1:-}"
    cd "$PROJECT_ROOT"
    if [[ -n "$service" ]]; then
        docker compose logs -f --tail=100 "$service"
    else
        docker compose logs -f --tail=50
    fi
}

# Menu tương tác (Interactive CLI)
interactive_menu() {
    while true; do
        echo -e "\n${BOLD}${CYAN}====================================================${NC}"
        echo -e "${BOLD}${CYAN}      LINUX DEVOPS SERVICE MANAGEMENT CLI           ${NC}"
        echo -e "${BOLD}${CYAN}====================================================${NC}"
        echo -e " 1) Xem trạng thái hệ thống (Status & Resource Usage)"
        echo -e " 2) Khởi động toàn bộ dịch vụ (Start All)"
        echo -e " 3) Tạm dừng dịch vụ (Stop All)"
        echo -e " 4) Đổi HTTP Port (Runtime Port Switch)"
        echo -e " 5) Chuyển đổi môi trường (Staging <-> Production)"
        echo -e " 6) Reload Nginx không downtime (SIGHUP Signal)"
        echo -e " 7) Chuyển mạch Blue-Green Deployment (Zero-Downtime Switch)"
        echo -e " 8) Xem live logs (FastAPI & Nginx)"
        echo -e " 9) Thoát (Exit)"
        echo -e "${CYAN}----------------------------------------------------${NC}"
        read -rp "Nhập lựa chọn của bạn [1-9]: " choice

        case "$choice" in
            1) show_status ;;
            2) start_services ;;
            3) stop_services ;;
            4) set_port "" ;;
            5) switch_environment "" ;;
            6) reload_nginx ;;
            7) "${PROJECT_ROOT}/scripts/blue_green_deploy.sh" "latest" ;;
            8) view_logs "" ;;
            9) echo -e "${GREEN}Tạm biệt!${NC}"; exit 0 ;;
            *) log_error "Lựa chọn không hợp lệ!" ;;
        esac
    done
}

# Entrypoint xử lý cờ lệnh hoặc menu
check_dependencies

case "${1:-}" in
    status)
        show_status
        ;;
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    reload)
        reload_nginx
        ;;
    set-port)
        set_port "${2:-}"
        ;;
    switch-env)
        switch_environment "${2:-}"
        ;;
    deploy-bg|switch-color)
        "${PROJECT_ROOT}/scripts/blue_green_deploy.sh" "${2:-latest}"
        ;;
    logs)
        view_logs "${2:-}"
        ;;
    help|--help|-h)
        echo "Sử dụng: $0 [status|start|stop|reload|set-port <port>|switch-env <env>|deploy-bg [tag]|logs <service>]"
        echo "Nếu chạy không có tham số, CLI Interactive Menu sẽ tự động mở."
        ;;
    "")
        interactive_menu
        ;;
    *)
        log_error "Lệnh '${1}' không tồn tại. Dùng '$0 --help' để xem hướng dẫn."
        exit 1
        ;;
esac

