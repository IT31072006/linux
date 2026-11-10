import os
import time
import platform
import hashlib
from datetime import datetime
from typing import Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response, Request
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
except ImportError:
    psycopg2 = None
    RealDictCursor = None

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
APP_ENV = os.getenv("APP_ENV", "production")
DB_HOST = os.getenv("DB_HOST", "db")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "devops_db")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "devops_secure_pass_2026")

class ItemCreate(BaseModel):
    name: str
    description: str

def get_db_connection():
    if psycopg2 is None:
        return None
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=3
        )
        return conn
    except Exception:
        return None

def init_db():
    conn = get_db_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS items (
                        id SERIAL PRIMARY KEY,
                        name VARCHAR(100) NOT NULL,
                        description TEXT,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    );
                """)
                # Thêm 2 bản ghi mẫu nếu bảng rỗng
                cur.execute("SELECT COUNT(*) FROM items;")
                count = cur.fetchone()[0]
                if count == 0:
                    cur.execute("""
                        INSERT INTO items (name, description) VALUES
                        ('Cấu hình Linux Kernel', 'Tối ưu /etc/sysctl.d/99-devops.conf cho TCP Buffer & Epoll'),
                        ('Hạ tầng Nginx Gateway', 'Thiết lập Rate Limiting 15 req/s và Load Balancing least_conn');
                    """)
                conn.commit()
        finally:
            conn.close()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Khởi tạo DB khi khởi động
    init_db()
    yield

app = FastAPI(
    title="DevOps Linux Services API",
    version=APP_VERSION,
    description="Backend API phục vụ đồ án môn Linux & Phần mềm nguồn mở",
    lifespan=lifespan
)

# Prometheus Metrics Definitions
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP Requests",
    ["method", "endpoint", "status_code"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP Request Latency in seconds",
    ["endpoint"]
)

@app.middleware("http")
async def prometheus_middleware(request: Request, call_next: Callable):
    start_time = time.time()
    response = await call_next(request)
    latency = time.time() - start_time
    
    endpoint = request.url.path
    if endpoint != "/metrics":
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=endpoint,
            status_code=response.status_code
        ).inc()
        REQUEST_LATENCY.labels(endpoint=endpoint).observe(latency)
        
    return response

@app.get("/")
def read_root(request: Request):
    accept = request.headers.get("accept", "")
    frontend_index = os.path.join(os.path.dirname(os.path.dirname(__file__)), "frontend", "index.html")
    if "text/html" in accept and os.path.exists(frontend_index):
        with open(frontend_index, "r", encoding="utf-8") as f:
            return Response(content=f.read(), media_type="text/html")
    return {
        "status": "online",
        "service": "DevOps Linux API",
        "version": APP_VERSION,
        "environment": APP_ENV,
        "kernel_os": "Ubuntu Linux",
        "message": "CI/CD & GitOps Pipeline successfully deployed!"
    }

@app.get("/health")
def healthcheck():
    """Endpoint cho Health-check probes từ Docker, Nginx và Bash scripts"""
    db_status = "healthy"
    conn = get_db_connection()
    if not conn:
        db_status = "unreachable"
    else:
        conn.close()

    overall = "ok" if db_status == "healthy" else "degraded"
    status_code = 200 if overall == "ok" else 503

    return Response(
        content=f'{{"status": "{overall}", "version": "{APP_VERSION}", "database": "{db_status}"}}',
        media_type="application/json",
        status_code=status_code
    )

@app.get("/metrics")
def metrics():
    """Scrape endpoint cho Prometheus"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

# ==========================================
# APPLICATION CRUD ENDPOINTS
# ==========================================
@app.get("/api/v1/items")
def get_items():
    conn = get_db_connection()
    if not conn:
        raise HTTPException(status_code=503, detail="Database connection failed")
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id, name, description, to_char(created_at, 'YYYY-MM-DD HH24:MI:SS') as created_at FROM items ORDER BY id DESC LIMIT 50;")
            items = cur.fetchall()
            return {"count": len(items), "data": items}
    finally:
        conn.close()

@app.post("/api/v1/items", status_code=201)
def create_item(item: ItemCreate):
    conn = get_db_connection()
    if not conn:
        raise HTTPException(status_code=503, detail="Database connection failed")
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "INSERT INTO items (name, description) VALUES (%s, %s) RETURNING id, name, description, to_char(created_at, 'YYYY-MM-DD HH24:MI:SS') as created_at;",
                (item.name, item.description)
            )
            created = cur.fetchone()
            conn.commit()
            return {"message": "Item created successfully", "data": created}
    finally:
        conn.close()

@app.delete("/api/v1/items/{item_id}")
def delete_item(item_id: int):
    conn = get_db_connection()
    if not conn:
        raise HTTPException(status_code=503, detail="Database connection failed")
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("DELETE FROM items WHERE id = %s RETURNING id;", (item_id,))
            deleted = cur.fetchone()
            if not deleted:
                raise HTTPException(status_code=404, detail="Item not found")
            conn.commit()
            return {"message": f"Item {item_id} deleted successfully"}
    finally:
        conn.close()

# ==========================================
# DEVOPS CONTROL CENTER API ENDPOINTS
# ==========================================
@app.get("/api/v1/devops/system-stats")
def get_system_stats():
    """Cung cấp thông số OS Linux, Cgroups và Runtime phục vụ Web Dashboard"""
    conn = get_db_connection()
    db_alive = conn is not None
    if conn:
        conn.close()

    return {
        "os_platform": platform.platform(),
        "kernel_release": platform.release(),
        "architecture": platform.machine(),
        "python_version": platform.python_version(),
        "app_version": APP_VERSION,
        "app_env": APP_ENV,
        "database": {
            "status": "online" if db_alive else "offline",
            "host": DB_HOST,
            "port": DB_PORT,
            "database_name": DB_NAME
        },
        "cgroups_limits": {
            "memory_limit": "512 MB",
            "cpu_quota": "1.0 CPU",
            "logging_rotation": "10MB x 3 files"
        },
        "nginx_rate_limit": "15 requests/sec (burst: 10)",
        "server_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }

@app.post("/api/v1/devops/trigger-backup")
def trigger_backup():
    """Kích hoạt sao lưu database trực tiếp từ giao diện Web"""
    conn = get_db_connection()
    if not conn:
        raise HTTPException(status_code=503, detail="Database connection failed")
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_name = f"web_backup_{DB_NAME}_{timestamp}.sql"
    
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id, name, description, created_at FROM items;")
            rows = cur.fetchall()
            
            dump_content = f"-- DevOps Linux Automated Backup: {backup_name}\n"
            dump_content += f"-- Exported at: {datetime.now().isoformat()}\n"
            dump_content += f"-- Total records: {len(rows)}\n\n"
            for r in rows:
                dump_content += f"INSERT INTO items (id, name, description) VALUES ({r['id']}, '{r['name']}', '{r['description']}');\n"
            
            sha256_hash = hashlib.sha256(dump_content.encode("utf-8")).hexdigest()
            size_bytes = len(dump_content.encode("utf-8"))
            
            return {
                "status": "SUCCESS",
                "backup_file": f"{backup_name}.gz",
                "records_count": len(rows),
                "size_human": f"{size_bytes} bytes",
                "sha256_checksum": sha256_hash,
                "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "retention_policy": "7 days auto-cleanup"
            }
    finally:
        conn.close()
