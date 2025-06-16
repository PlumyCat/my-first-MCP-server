# My First MCP - Serveur Météo

Un serveur MCP (Model Context Protocol) simple qui fournit des données météorologiques factices.

## Structure du Projet

```
my_first_mcp/
├── src/
│   ├── __init__.py
│   ├── main.py           # Point d'entrée principal
│   ├── server.py         # Configuration du serveur MCP
│   └── tools/
│       ├── __init__.py
│       └── weather.py    # Outil météo factice
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
└── README.md
```

## Fonctionnalités

- **Outil météo** : Retourne des données météorologiques factices pour n'importe quelle ville
- **Support unités** : Celsius et Fahrenheit
- **Prévisions** : Inclut des prévisions sur 2 jours
- **Données complètes** : Température, humidité, vent, pression, etc.

## Installation et Démarrage

### Méthode 1 : Docker Compose (Recommandée)

```bash
# Cloner ou créer le projet
cd my_first_mcp

# Construire et démarrer le serveur
docker-compose up --build

# Pour arrêter
docker-compose down
```

### Méthode 2 : Docker simple

```bash
# Construire l'image
docker build -t mcp-weather-server .

# Démarrer le container
docker run -it --name mcp-weather mcp-weather-server
```

### Méthode 3 : Installation locale

```bash
# Installer les dépendances
pip install -r requirements.txt

# Démarrer le serveur
python -m src.main
```

## Utilisation

Le serveur MCP expose un outil `get_weather` avec les paramètres suivants :

- **city** (requis) : Nom de la ville
- **unit** (optionnel) : "celsius" ou "fahrenheit" (défaut: celsius)

### Exemple d'appel

```json
{
  "tool": "get_weather",
  "arguments": {
    "city": "Paris",
    "unit": "celsius"
  }
}
```

### Exemple de réponse

```json
{
  "success": true,
  "data": {
    "city": "Paris",
    "temperature": 22,
    "unit": "°C",
    "condition": "ensoleillé",
    "humidity": 65,
    "wind_speed": 12,
    "wind_unit": "km/h",
    "pressure": 1013,
    "visibility": 10,
    "uv_index": 6,
    "timestamp": "2025-06-13T14:30:00",
    "forecast": [
      {
        "day": "Demain",
        "high": 25,
        "low": 15,
        "condition": "partiellement nuageux"
      }
    ]
  },
  "message": "Données météo récupérées pour Paris"
}
```

## Test du Serveur

Pour tester votre serveur MCP :

1. Démarrez le serveur avec Docker
2. Utilisez un client MCP ou testez via stdin/stdout
3. Les logs apparaîtront dans la console Docker

## Développement

Pour modifier le code en développement :
- Les volumes Docker sont configurés pour le rechargement automatique
- Modifiez les fichiers dans `src/` et redémarrez le container

## Prochaines Étapes

- Intégrer une vraie API météo (OpenWeatherMap, etc.)
- Ajouter d'autres outils (géolocalisation, historique, etc.)
- Déployer sur Azure Container Instances ou Azure Functions