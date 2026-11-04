# Imagem da aplicação demo. Build: docker build -t lab-app:1.0.0 --build-arg APP_VERSION=1.0.0 app/
FROM python:3.12-slim
ARG APP_VERSION=1.0.0
ENV APP_VERSION=${APP_VERSION} PYTHONUNBUFFERED=1
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
# usuário sem privilégios (boa prática; o Trivy também avalia isso)
RUN useradd -r -u 10001 appuser
USER 10001
EXPOSE 8080
# 1 worker + 4 threads: simples e suficiente para o lab
CMD ["gunicorn", "-b", "0.0.0.0:8080", "-w", "1", "--threads", "4", "app:app"]
