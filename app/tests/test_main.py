import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_read_root():
    """Kiểm tra endpoint root trả về status 200 và thông tin phiên bản hợp lệ"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "online"
    assert "version" in data
    assert "environment" in data

def test_metrics_endpoint():
    """Kiểm tra endpoint Prometheus metrics hoạt động và trả về text/plain metrics"""
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_requests_total" in response.text

def test_healthcheck_endpoint():
    """
    Kiểm tra endpoint healthcheck.
    Lưu ý: Trong môi trường unit test không có DB thật, healthcheck trả về degraded (503)
    hoặc 200 nếu có mock/db. Test này đảm bảo endpoint trả về đúng cấu trúc JSON.
    """
    response = client.get("/health")
    assert response.status_code in [200, 503]
    data = response.json()
    assert "status" in data
    assert "version" in data
    assert "database" in data

def test_devops_system_stats():
    """Kiểm tra endpoint cung cấp thông số OS Linux và Cgroups cho Frontend Dashboard"""
    response = client.get("/api/v1/devops/system-stats")
    assert response.status_code == 200
    data = response.json()
    assert "os_platform" in data
    assert "kernel_release" in data
    assert "cgroups_limits" in data
    assert "app_version" in data
    assert "nginx_rate_limit" in data

def test_items_endpoint_structure():
    """Kiểm tra endpoint danh sách items (trả về 200 nếu có DB, hoặc 503 nếu chưa kết nối)"""
    response = client.get("/api/v1/items")
    assert response.status_code in [200, 503]
