# ==========================================
# Multi-stage Dockerfile cho Python FastAPI
# Tối ưu kích thước image & bảo mật Linux non-root
# ==========================================

# Stage 1: Build dependencies
FROM python:3.11-slim AS builder

WORKDIR /build

# Cài đặt công cụ build cần thiết cho thư viện C (như psycopg2)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Final Production Runtime
FROM python:3.11-slim

LABEL maintainer="DevOps Team <devops-team@linux-project.local>"
LABEL description="FastAPI Production Service with Prometheus Instrumentation"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/home/appuser/.local/bin:$PATH"

WORKDIR /app

# Cài đặt runtime libraries cho PostgreSQL và curl (phục vụ healthcheck)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Bảo mật Linux: Tạo non-root user và group riêng biệt để tuân thủ Least Privilege
RUN groupadd -g 10001 appuser && \
    useradd -u 10001 -g appuser -m -s /bin/bash appuser

# Copy dependencies từ builder stage vào thư mục của appuser
COPY --from=builder /root/.local /home/appuser/.local

# Copy source code và phân quyền chặt chẽ
COPY --chown=appuser:appuser . /app

# Chuyển sang user không có quyền root
USER appuser

EXPOSE 8000

# Docker healthcheck định kỳ kiểm tra tiến trình
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", "--access-log"]

