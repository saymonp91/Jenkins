from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert "message" in response.json()


def test_get_item():
    response = client.get("/items/1")
    assert response.status_code == 200
    assert response.json()["item_id"] == 1