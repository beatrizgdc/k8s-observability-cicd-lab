"""Testes da aplicação demo (executados no estágio 'Test' do Jenkins)."""
import app as lab


def client():
    return lab.app.test_client()


def test_healthz():
    r = client().get("/healthz")
    assert r.status_code == 200 and r.json["status"] == "ok"


def test_readyz():
    assert client().get("/readyz").status_code == 200


def test_hello():
    assert client().get("/api/hello").json["message"].startswith("olá")


def test_error_endpoint_returns_500():
    assert client().get("/error").status_code == 500


def test_info_has_version():
    assert "version" in client().get("/info").json


def test_metrics_exposed():
    client().get("/api/hello")
    body = client().get("/metrics").data.decode()
    assert "http_requests_total" in body


def test_index_lists_endpoints():
    assert "/healthz" in client().get("/").json["endpoints"]


def test_work_ok_by_default():
    assert client().get("/api/work").json["result"] == "ok"


def test_work_fails_when_error_rate_is_1(monkeypatch):
    monkeypatch.setenv("FAULT_ERROR_RATE", "1")
    assert client().get("/api/work").status_code == 500


def test_health_fails_when_flag_set(monkeypatch):
    monkeypatch.setenv("FAIL_HEALTH", "1")
    assert client().get("/healthz").status_code == 503
    assert client().get("/readyz").status_code == 503


def test_slow_cpu_memory_zero_cost():
    assert client().get("/slow?seconds=0").json["slept"] == 0
    assert client().get("/cpu?seconds=0").status_code == 200
    assert client().get("/memory?mb=1").json["allocated_mb"] == 1
