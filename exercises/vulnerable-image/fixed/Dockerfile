# Versão corrigida: base atual, dependências atualizadas, usuário não-root, sem segredo em ENV.
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN useradd -r -u 10001 appuser
USER 10001
CMD ["python", "app.py"]
