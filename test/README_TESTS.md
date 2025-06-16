# 🧪 Scripts de Test MCP Weather Server

Ce dossier contient plusieurs scripts de test pour valider le fonctionnement du serveur MCP Weather dans différents environnements.

## 📋 Vue d'ensemble des scripts

### 🏠 Tests Locaux (Serveur Python direct)
- **`test_azure_openai_api.py`** - Teste le serveur local avec Azure OpenAI API
- **`test_claude_api.py`** - Teste le serveur local avec Claude API

### 🐳 Tests Docker Local
- **`test_docker_local.py`** - Teste le serveur dans un container Docker local

### ☁️ Tests Déploiement Azure
- **`test_azure_deployment.py`** - Teste le serveur déployé sur Azure Container Instances

### 🌍 Test Unifié Multi-Environnements
- **`test_environments.py`** - Script unifié pour tester tous les environnements

## 🔧 Configuration requise

### Variables d'environnement de base
```bash
# API Météo (obligatoire pour tous les tests)
OPENWEATHER_API_KEY=your_openweather_api_key

# Azure OpenAI (optionnel)
AZURE_OPENAI_API_KEY=your_azure_openai_key
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/
AZURE_OPENAI_DEPLOYMENT_NAME=your_deployment_name
AZURE_OPENAI_API_VERSION=2024-05-01-preview

# Claude API (optionnel)
ANTHROPIC_API_KEY=sk-ant-api03-...

# Azure AD pour déploiement sécurisé (pour tests Azure)
AZURE_AD_TENANT_ID=your-tenant-id
AZURE_AD_CLIENT_ID=your-client-id
AZURE_AD_CLIENT_SECRET=your-client-secret

# URL du serveur déployé (pour tests Azure)
AZURE_SERVER_URL=http://your-container.azurecontainer.io:8000
```

### Dépendances Python
```bash
pip install openai anthropic requests python-dotenv
```

## 🚀 Utilisation des scripts

### 1. Test Local avec Azure OpenAI
```bash
python test/test_azure_openai_api.py
```
**Ce qu'il teste :**
- Démarre le serveur MCP local (`python -m src.main`)
- Initialise la connexion MCP
- Récupère des données météo via MCP
- Envoie les données à Azure OpenAI pour analyse
- Teste 6 scénarios différents avec statistiques

### 2. Test Local avec Claude
```bash
python test/test_claude_api.py
```
**Ce qu'il teste :**
- Démarre le serveur MCP local
- Récupère des données météo via MCP
- Envoie les données à Claude pour analyse
- Teste 5 scénarios différents

### 3. Test Docker Local
```bash
python test/test_docker_local.py
```
**Ce qu'il teste :**
- Construit l'image Docker du serveur MCP
- Démarre un container local
- Teste la connectivité HTTP
- Teste les appels MCP via HTTP
- Teste l'intégration avec Azure OpenAI/Claude
- Nettoie automatiquement le container

### 4. Test Déploiement Azure
```bash
python test/test_azure_deployment.py
```
**Ce qu'il teste :**
- Connectivité avec le serveur Azure
- Authentification Azure AD
- Appels MCP sécurisés
- Intégration avec Azure OpenAI/Claude
- Gestion des tokens Azure AD

### 5. Test Unifié Multi-Environnements
```bash
# Tester tous les environnements
python test/test_environments.py --all

# Tester seulement l'environnement local
python test/test_environments.py --env local

# Tester Docker et Azure
python test/test_environments.py --env docker --env azure
```

## 📊 Interprétation des résultats

### ✅ Succès
- **Local** : Le serveur Python fonctionne correctement
- **Docker** : Le container est opérationnel
- **Azure** : Le déploiement cloud est fonctionnel

### ❌ Échecs courants et solutions

#### Erreur "API météo non configurée"
```bash
# Solution : Ajoutez votre clé OpenWeather
OPENWEATHER_API_KEY=your_key_here
```

#### Erreur "Docker non disponible"
```bash
# Solution : Installez Docker
# Windows: https://docs.docker.com/desktop/windows/
# Linux: sudo apt install docker.io
```

#### Erreur "Serveur Azure inaccessible"
```bash
# Solutions possibles :
# 1. Vérifiez l'URL du serveur
AZURE_SERVER_URL=http://correct-url:8000

# 2. Vérifiez que le container Azure tourne
az container show --resource-group your-rg --name your-container

# 3. Vérifiez les règles de pare-feu
```

#### Erreur "Authentification Azure AD échouée"
```bash
# Solution : Vérifiez vos identifiants Azure AD
AZURE_AD_TENANT_ID=correct-tenant-id
AZURE_AD_CLIENT_ID=correct-client-id
AZURE_AD_CLIENT_SECRET=correct-secret
```

## 🎯 Stratégie de test recommandée

### 1. Développement Local
```bash
# Commencez par tester localement
python test/test_claude_api.py
# ou
python test/test_azure_openai_api.py
```

### 2. Validation Docker
```bash
# Testez le container avant déploiement
python test/test_docker_local.py
```

### 3. Validation Déploiement
```bash
# Testez le déploiement Azure
python test/test_azure_deployment.py
```

### 4. Test Complet
```bash
# Test final de tous les environnements
python test/test_environments.py --all
```

## 🔍 Détails techniques

### Architecture des tests
```
Test Script
    ↓
MCP Server (Local/Docker/Azure)
    ↓
Weather API (OpenWeather)
    ↓
AI API (Azure OpenAI/Claude)
    ↓
Formatted Response
```

### Protocole MCP utilisé
- **Version** : 2024-11-05
- **Transport** : JSON-RPC 2.0
- **Outils** : `get_weather(city, unit)`
- **Format** : Réponses JSON structurées

### Sécurité
- **Local** : Aucune authentification
- **Docker** : Variables d'environnement
- **Azure** : Authentification Azure AD + HTTPS

## 🐛 Dépannage

### Logs détaillés
```bash
# Pour voir les logs détaillés, ajoutez :
export PYTHONUNBUFFERED=1
python test/your_test_script.py
```

### Test de connectivité de base
```bash
# Test manuel de l'API météo
curl "http://api.openweathermap.org/data/2.5/weather?q=Paris&appid=YOUR_KEY"

# Test manuel du serveur Azure
curl -H "Authorization: Bearer YOUR_TOKEN" http://your-server:8000/health
```

### Vérification des dépendances
```bash
python -c "import openai, anthropic, requests; print('✅ Toutes les dépendances sont installées')"
```

## 📈 Métriques de performance

Les scripts mesurent :
- **Temps de réponse** des APIs
- **Débit** (caractères/seconde)
- **Taux de succès** des appels
- **Latence réseau** (pour Azure)

## 🎉 Résultats attendus

Un déploiement réussi devrait afficher :
```
🎉 RÉSUMÉ FINAL MULTI-ENVIRONNEMENTS
==================================================
   🏠 Local: ✅ RÉUSSI
   🐳 Docker: ✅ RÉUSSI  
   ☁️ Azure: ✅ RÉUSSI

📊 Score global: 3/3
🎉 Tous les environnements fonctionnent parfaitement !
``` 