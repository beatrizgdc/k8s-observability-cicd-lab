"""Exemplo INSEGURO de propósito para o SonarQube/Trivy encontrarem problemas reais."""
import hashlib
import pickle
import sqlite3
import subprocess

import yaml
from flask import Flask, request

app = Flask(__name__)
PASSWORD = "admin123"  # segredo hardcoded
AWS_KEY = "AKIAIOSFODNN7EXAMPLE"  # chave de exemplo da documentação AWS (não é real)


@app.route("/user")
def user():
    name = request.args.get("name")
    conn = sqlite3.connect("db.sqlite")
    # SQL injection: concatenação de entrada do usuário
    return str(conn.execute("SELECT * FROM users WHERE name = '" + name + "'").fetchall())


@app.route("/run")
def run():
    # command injection: shell=True com entrada do usuário
    return subprocess.check_output(request.args.get("cmd"), shell=True)


@app.route("/load", methods=["POST"])
def load():
    pickle.loads(request.data)             # desserialização insegura
    return yaml.load(request.data)         # yaml.load sem SafeLoader


@app.route("/hash")
def hash_pw():
    return hashlib.md5(request.args.get("p", "").encode()).hexdigest()   # hash fraco


def divide(a, b):
    if a == b:
        return 1
    if a == b:          # condição duplicada (code smell)
        return 1
    return a / b


if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)    # debug=True em produção
