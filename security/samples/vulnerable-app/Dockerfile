# Dockerfile de demonstração com problemas propositais: base antiga, root, segredo em ENV.
FROM python:3.8-slim-buster
ENV DB_PASSWORD=SuperSecret123
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
