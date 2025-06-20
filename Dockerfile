# Dockerfile pour serveur MCP HTTP (tests Docker)
FROM python:3.12-slim

# Définition du répertoire de travail
WORKDIR /app

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copie du fichier requirements
COPY requirements.txt .

# Installation des dépendances Python + serveur HTTP
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir fastapi uvicorn PyJWT cryptography

# Copie du code source
COPY src/ ./src/

# Variables d'environnement
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
ENV MCP_SERVER_MODE=http

# Exposition du port HTTP
EXPOSE 8000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Commande pour démarrer le serveur HTTP
CMD ["uvicorn", "src.http_server:app", "--host", "0.0.0.0", "--port", "8000", "--log-level", "info"] 