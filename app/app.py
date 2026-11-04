"""
Aplicação demo do DevOps Lab (Flask).

Foi escrita para ser lida em 5 minutos: cada endpoint existe para treinar
um tipo de diagnóstico. Não é preciso entender Flask para usar o lab.

Falhas injetáveis por variável de ambiente (simulam "deploys ruins"):
  FAULT_ERROR_RATE   0.0-1.0  fração de requisições em /api/work que viram HTTP 500
  FAULT_LATENCY_MS   int      latência extra (ms) adicionada em /api/work
  FAIL_HEALTH        "1"      faz /healthz e /readyz retornarem 503
  FAIL_AT_STARTUP    "1"      o processo encerra com erro ao iniciar (CrashLoopBackOff)
  REQUIRED_CONFIG    nome de variável obrigatória; se ausente o app encerra
"""
import json
import logging
import os
import random
import socket
import sys
import threading
import time

from flask import Flask, Response, g, jsonify, request
from prometheus_client import (CONTENT_TYPE_LATEST, Counter, Gauge, Histogram,
                               generate_latest)

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
START_TIME = time.time()


# ---------- logs estruturados (uma linha JSON por evento) ----------
class JsonFormatter(logging.Formatter):
    def format(self, record):
        data = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "msg": record.getMessage(),
            "app_version": APP_VERSION,
        }
        data.update(getattr(record, "extra_fields", {}))
        return json.dumps(data)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
log = logging.getLogger("lab-app")
log.setLevel(logging.INFO)
log.addHandler(handler)
log.propagate = False
logging.getLogger("werkzeug").setLevel(logging.WARNING)


def event(msg, level=logging.INFO, **fields):
    log.log(level, msg, extra={"extra_fields": fields})


# ---------- falhas de inicialização (para exercícios) ----------
required = os.getenv("REQUIRED_CONFIG")
if required and not os.getenv(required):
    event(f"variável obrigatória {required} ausente; encerrando", logging.ERROR)
    sys.exit(3)
if os.getenv("FAIL_AT_STARTUP") == "1":
    event("FAIL_AT_STARTUP=1: simulando crash na inicialização", logging.ERROR)
    sys.exit(1)

# ---------- métricas Prometheus ----------
REQS = Counter("http_requests_total", "Total de requisições", ["method", "path", "status"])
LAT = Histogram("http_request_duration_seconds", "Latência das requisições", ["path"],
                buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10))
INFLIGHT = Gauge("http_requests_in_flight", "Requisições em andamento (saturação)")

app = Flask(__name__)

# ---------- tracing OpenTelemetry (opcional) ----------
# Só ativa se OTEL_EXPORTER_OTLP_ENDPOINT estiver definido (ver observability/).
if os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"):
    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
        from opentelemetry.instrumentation.flask import FlaskInstrumentor
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor

        provider = TracerProvider(resource=Resource.create({"service.name": "lab-app"}))
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
        trace.set_tracer_provider(provider)
        FlaskInstrumentor().instrument_app(app, excluded_urls="metrics,healthz,readyz")
        event("tracing OpenTelemetry ativado")
    except Exception as exc:  # não derruba o app se o tracing falhar
        event(f"tracing desativado: {exc}", logging.WARNING)

_hold = []  # memória "vazada" de propósito por /memory


@app.before_request
def _start():
    g.t0 = time.time()
    INFLIGHT.inc()


@app.after_request
def _end(resp):
    elapsed = time.time() - g.t0
    path = request.url_rule.rule if request.url_rule else "desconhecido"
    LAT.labels(path).observe(elapsed)
    REQS.labels(request.method, path, resp.status_code).inc()
    INFLIGHT.dec()
    if path not in ("/metrics", "/healthz", "/readyz"):
        event("request", method=request.method, path=request.path, status=resp.status_code,
              duration_ms=round(elapsed * 1000, 1), pod=socket.gethostname())
    return resp


@app.get("/")
def index():
    return jsonify(app="lab-app", version=APP_VERSION, endpoints=[
        "/healthz", "/readyz", "/api/hello", "/api/work", "/error", "/slow?seconds=2",
        "/cpu?seconds=20", "/memory?mb=100", "/info", "/metrics"])


@app.get("/healthz")  # liveness: "o processo está vivo?"
def healthz():
    if os.getenv("FAIL_HEALTH") == "1":
        return jsonify(status="falhando"), 503
    return jsonify(status="ok")


@app.get("/readyz")  # readiness: "posso receber tráfego?"
def readyz():
    if os.getenv("FAIL_HEALTH") == "1":
        return jsonify(status="nao-pronto"), 503
    return jsonify(status="pronto")


@app.get("/api/hello")  # endpoint de teste simples
def hello():
    return jsonify(message="olá do lab", pod=socket.gethostname(), version=APP_VERSION)


@app.get("/api/work")  # simula trabalho real; sofre as falhas injetadas
def work():
    latency = int(os.getenv("FAULT_LATENCY_MS", "0"))
    time.sleep(latency / 1000 + random.uniform(0.005, 0.03))
    if random.random() < float(os.getenv("FAULT_ERROR_RATE", "0")):
        event("falha simulada em /api/work", logging.ERROR, error="backend indisponivel")
        return jsonify(error="erro interno simulado"), 500
    return jsonify(result="ok", pod=socket.gethostname())


@app.get("/error")  # sempre HTTP 500
def error():
    event("erro 500 proposital", logging.ERROR, error="endpoint /error chamado")
    return jsonify(error="erro 500 proposital"), 500


@app.get("/slow")  # lentidão controlada: /slow?seconds=3
def slow():
    seconds = min(float(request.args.get("seconds", 2)), 30)
    time.sleep(seconds)
    return jsonify(slept=seconds)


@app.get("/cpu")  # consome 1 core por N segundos (em segundo plano)
def cpu():
    seconds = min(int(request.args.get("seconds", 20)), 600)

    def burn():
        end = time.time() + seconds
        while time.time() < end:
            sum(i * i for i in range(10000))

    threading.Thread(target=burn, daemon=True).start()
    event("consumo de CPU iniciado", seconds=seconds)
    return jsonify(burning_cpu_seconds=seconds)


@app.get("/memory")  # aloca N MB e NÃO libera (simula memory leak)
def memory():
    mb = min(int(request.args.get("mb", 100)), 4096)
    _hold.append(bytearray(mb * 1024 * 1024))
    for i in range(0, len(_hold[-1]), 4096):  # força uso real da RAM
        _hold[-1][i] = 1
    event("memória alocada", mb=mb, total_blocks=len(_hold))
    return jsonify(allocated_mb=mb, blocks=len(_hold))


@app.get("/info")
def info():
    return jsonify(app="lab-app", version=APP_VERSION, hostname=socket.gethostname(),
                   uptime_seconds=round(time.time() - START_TIME),
                   python=sys.version.split()[0],
                   faults={k: os.getenv(k) for k in
                           ("FAULT_ERROR_RATE", "FAULT_LATENCY_MS", "FAIL_HEALTH") if os.getenv(k)})


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), threaded=True)
