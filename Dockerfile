# Utilisation de l'image Python officielle (version stable)
FROM python:3.12-slim

# Définition du répertoire de travail
WORKDIR /app

# Installation des dépendances système si nécessaire
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copie du fichier requirements
COPY requirements.txt .

# Installation des dépendances Python
RUN pip install --no-cache-dir -r requirements.txt

# Copie du code source
COPY src/ ./src/

# Variables d'environnement
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Exposition du port (optionnel pour MCP stdio)
EXPOSE 8000

# Commande par défaut
CMD ["python", "-m", "src.main"]