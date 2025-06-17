# 🌤️ MCP Weather Server

Un serveur MCP (Model Context Protocol) pour les informations météorologiques avec authentification Azure AD et déploiement Azure Container Instances.

## 📋 Table des matières

- [Fonctionnalités](#-fonctionnalités)
- [Installation](#-installation)
  - [Option 1: Installation PowerShell (Windows)](#option-1-installation-powershell-windows)
  - [Option 2: Installation Shell (Linux/macOS)](#option-2-installation-shell-linuxmacos)
- [Configuration](#-configuration)
- [Utilisation](#-utilisation)
- [Tests](#-tests)
- [Déploiement Azure](#-déploiement-azure)
- [Sécurisation Azure AD](#-sécurisation-azure-ad)
- [Structure du projet](#-structure-du-projet)

## ✨ Fonctionnalités

- 🌡️ **API météo en temps réel** avec données de température, conditions et localisation
- 🔐 **Authentification Azure AD** avec tokens JWT sécurisés
- ☁️ **Déploiement Azure** sur Container Instances avec registre privé
- 🤖 **Intégration IA** : Compatible Azure OpenAI et Claude API
- 🐳 **Containerisé** : Docker avec healthcheck et logs
- 🧪 **Tests complets** : Local, Docker, Azure avec authentification
- 📊 **Monitoring** : Scripts de gestion et surveillance Azure

## 🚀 Installation

### Option 1: Installation PowerShell (Windows)

#### Prérequis
- Windows 10/11 avec PowerShell 7+
- Azure CLI installé
- Docker Desktop installé
- Compte Azure avec permissions Container Instances

#### Installation complète

1. **Cloner le repository**
```powershell
git clone https://github.com/votre-username/mcp-weather-server.git
cd mcp-weather-server
```

2. **Configuration des variables d'environnement**
```powershell
# Copier le fichier d'exemple
Copy-Item "env_example.txt" ".env"

# Éditer le fichier .env avec vos clés
notepad .env
```

3. **Déploiement Azure**
```powershell
# Se connecter à Azure
az login

# Déployer le serveur (script principal)
.\deploy-azure.ps1

# Sécuriser avec Azure AD (après déploiement)
.\azure-secure.ps1
```

4. **Tests et validation**
```powershell
# Tester le déploiement complet
python test/test_azure_deployment.py

# Gérer le serveur Azure
.\azure-manage.ps1 status
.\azure-manage.ps1 logs
```

### Option 2: Installation Shell (Linux/macOS)

#### Prérequis
- Linux/macOS avec Bash
- Azure CLI installé
- Docker installé
- Compte Azure avec permissions Container Instances

#### Installation complète

1. **Cloner le repository**
```bash
git clone https://github.com/votre-username/mcp-weather-server.git
cd mcp-weather-server
```

2. **Configuration des variables d'environnement**
```bash
# Copier le fichier d'exemple
cp env_example.txt .env

# Éditer le fichier .env avec vos clés
nano .env
```

3. **Déploiement Azure**
```bash
# Se connecter à Azure
az login

# Rendre les scripts exécutables
chmod +x deploiement/*.sh

# Déployer le serveur (script principal)
./deploiement/deploy-azure.sh

# Sécuriser avec Azure AD (optionnel - depuis Windows)
# Ou utiliser les scripts de gestion Linux
./deploiement/azure-manage.sh status
```

4. **Tests et validation**
```bash
# Tester le déploiement
python test/test_azure_deployment.py

# Gérer le serveur Azure
./deploiement/azure-manage.sh logs
./deploiement/azure-manage.sh restart
```

## ⚙️ Configuration

### Variables d'environnement (.env)

```env
# Configuration du serveur
PORT=8000
HOST=0.0.0.0
ENVIRONMENT=production
LOG_LEVEL=INFO

# Azure AD (requis pour la sécurisation)
AZURE_AD_TENANT_ID=your_tenant_id_here
AZURE_AD_CLIENT_ID=your_client_id_here
AZURE_AD_CLIENT_SECRET=your_client_secret_here

# URL du serveur Azure (mise à jour automatique)
AZURE_SERVER_URL=http://your-container.azurecontainer.io:8000

# APIs IA (optionnel pour tests)
AZURE_OPENAI_API_KEY=your_azure_openai_key_here
AZURE_OPENAI_ENDPOINT=your_azure_openai_endpoint_here
AZURE_OPENAI_DEPLOYMENT_NAME=gpt-4
ANTHROPIC_API_KEY=your_claude_api_key_here

# APIs météo (optionnel)
OPENWEATHERMAP_API_KEY=your_openweathermap_key_here
WEATHERAPI_KEY=your_weatherapi_key_here
```

### Configuration Azure AD

1. **Créer une application Azure AD**
```bash
# Via Azure CLI
az ad app create --display-name "mcp-weather-server" --sign-in-audience "AzureADMyOrg"
```

2. **Configurer les permissions**
- Ajouter les permissions API nécessaires
- Générer un secret client
- Noter le Tenant ID, Client ID et Client Secret

## 🎯 Utilisation

### Déploiement rapide

**Windows (PowerShell) :**
```powershell
# Déploiement + sécurisation en une fois
.\deploy-azure.ps1 && .\azure-secure.ps1
```

**Linux/macOS (Shell) :**
```bash
# Déploiement complet
./deploiement/deploy-azure.sh
```

### Gestion du serveur

**Windows :**
```powershell
# État du serveur
.\azure-manage.ps1 status

# Voir les logs
.\azure-manage.ps1 logs

# Redémarrer
.\azure-manage.ps1 restart

# URL du serveur
.\azure-manage.ps1 url
```

**Linux/macOS :**
```bash
# État du serveur
./deploiement/azure-manage.sh status

# Voir les logs
./deploiement/azure-manage.sh logs

# Redémarrer
./deploiement/azure-manage.sh restart
```

## 🧪 Tests

### Tests disponibles

```powershell
# Test complet du déploiement Azure
python test/test_azure_deployment.py

# Test des APIs IA localement
python test/test_azure_openai_api.py
python test/test_claude_api.py

# Test du container Docker local
python test/test_docker_local.py

# Comparaison des APIs IA
python test/compare_ai_apis.py
```

### Environnements de test

```powershell
# Tester différents environnements
python test/test_environments.py --env local
python test/test_environments.py --env docker
python test/test_environments.py --env azure
```

## ☁️ Déploiement Azure

### Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Azure CLI     │───▶│  Container       │───▶│  Azure Container│
│   (Local)       │    │  Registry (ACR)  │    │  Instances (ACI)│
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │   Docker Image   │
                       │  MCP Weather     │
                       │  + FastAPI       │
                       │  + Azure AD      │
                       └──────────────────┘
```

### Processus de déploiement

1. **Création du registre Azure Container Registry (ACR)**
2. **Construction et push de l'image Docker**
3. **Déploiement sur Azure Container Instances (ACI)**
4. **Configuration réseau et DNS**
5. **Sécurisation avec Azure AD**

### Ressources créées

- **Groupe de ressources** : `mcp-weather-rg`
- **Container Registry** : `mcpweatherXXXXXX.azurecr.io`
- **Container Instance** : `mcp-weather-server`
- **IP publique** avec FQDN : `mcp-weather-XXXXXX.francecentral.azurecontainer.io`

## 🔐 Sécurisation Azure AD

### Workflow de sécurisation

1. **Serveur non sécurisé** (après déploiement initial)
   - Accessible sans authentification
   - Tests de base fonctionnels

2. **Activation Azure AD** (via `azure-secure.ps1`)
   - Suppression du container existant
   - Recréation avec variables Azure AD
   - Mode sécurisé activé

3. **Serveur sécurisé** (résultat final)
   - Authentification Bearer token requise
   - Validation JWT Azure AD
   - Tests complets avec authentification

### Authentification

```javascript
// Exemple d'appel authentifié
const response = await fetch('http://your-server:8000/mcp', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer ' + azureAdToken,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
      name: "get_weather",
      arguments: { city: "Paris" }
    }
  })
});
```

## 📁 Structure du projet

```
mcp-weather-server/
├── 📄 README.md                    # Documentation principale
├── 📄 requirements.txt             # Dépendances Python
├── 📄 Dockerfile                   # Image Docker principale
├── 📄 docker-compose.yml           # Orchestration locale
├── 📄 .env                         # Variables d'environnement
├── 📄 env_example.txt              # Exemple de configuration
├── 📄 mcp_config_example.json      # Configuration MCP exemple
├── 📄 .gitignore                   # Fichiers ignorés par Git
│
├── 📂 src/                         # Code source
│   ├── 📄 __init__.py
│   ├── 📄 main.py                  # Point d'entrée MCP stdio
│   ├── 📄 server.py                # Serveur MCP principal
│   ├── 📄 http_server.py           # Serveur HTTP/REST
│   ├── 📄 auth.py                  # Authentification Azure AD
│   └── 📂 tools/
│       ├── 📄 __init__.py
│       └── 📄 weather.py           # Outil météo MCP
│
├── 📂 test/                        # Tests et validation
│   ├── 📄 README_TESTS.md          # Documentation des tests
│   ├── 📄 test_azure_deployment.py # Test déploiement Azure
│   ├── 📄 test_azure_openai_api.py # Test Azure OpenAI
│   ├── 📄 test_claude_api.py       # Test Claude API
│   ├── 📄 test_docker_local.py     # Test Docker local
│   ├── 📄 test_mcp_server.py       # Test serveur MCP
│   ├── 📄 test_environments.py     # Test multi-environnements
│   ├── 📄 compare_ai_apis.py       # Comparaison APIs IA
│   ├── 📄 test_with_ai.py          # Tests avec IA
│   └── 📄 run_local.py             # Exécution locale
│
├── 📂 deploiement/                 # Scripts de déploiement
│   ├── 📄 README_LINUX.md          # Documentation Linux
│   ├── 📄 deploy-azure.sh          # Déploiement Azure (Linux)
│   ├── 📄 azure-setup.sh           # Configuration Azure (Linux)
│   ├── 📄 azure-manage.sh          # Gestion Azure (Linux)
│   ├── 📄 azure-cleanup.sh         # Nettoyage Azure (Linux)
│   ├── 📄 azure-update-http.sh     # Mise à jour HTTP (Linux)
│   ├── 📄 test-linux-scripts.sh    # Tests scripts Linux
│   ├── 📄 deploy-azure.ps1         # Déploiement Azure (Windows)
│   ├── 📄 azure-setup.ps1          # Configuration Azure (Windows)
│   ├── 📄 azure-manage.ps1         # Gestion Azure (Windows)
│   ├── 📄 azure-cleanup.ps1        # Nettoyage Azure (Windows)
│   └── 📄 azure-update-http.ps1    # Mise à jour HTTP (Windows)
│
├── 📄 deploy-azure.ps1             # Script de déploiement principal
├── 📄 azure-manage.ps1             # Script de gestion principal
├── 📄 azure-secure.ps1             # Script de sécurisation Azure AD
├── 📄 azure-secure-keyvault.ps1    # Sécurisation avec Key Vault
└── 📄 azure-get-token.ps1          # Génération de tokens Azure AD
```

## 🔧 Scripts principaux

### Windows (PowerShell)

| Script | Description | Usage |
|--------|-------------|-------|
| `deploy-azure.ps1` | Déploiement complet sur Azure | `.\deploy-azure.ps1` |
| `azure-secure.ps1` | Sécurisation avec Azure AD | `.\azure-secure.ps1` |
| `azure-manage.ps1` | Gestion du serveur Azure | `.\azure-manage.ps1 status` |
| `azure-get-token.ps1` | Test des tokens Azure AD | `.\azure-get-token.ps1` |

### Linux/macOS (Shell)

| Script | Description | Usage |
|--------|-------------|-------|
| `deploy-azure.sh` | Déploiement complet sur Azure | `./deploiement/deploy-azure.sh` |
| `azure-manage.sh` | Gestion du serveur Azure | `./deploiement/azure-manage.sh status` |
| `azure-setup.sh` | Configuration initiale Azure | `./deploiement/azure-setup.sh` |
| `azure-cleanup.sh` | Nettoyage des ressources | `./deploiement/azure-cleanup.sh` |

## 🎯 Workflow recommandé

### Première installation

1. **Déploiement initial** (choisir votre plateforme)
   - Windows : `.\deploy-azure.ps1`
   - Linux : `./deploiement/deploy-azure.sh`

2. **Sécurisation** (recommandé)
   - Windows : `.\azure-secure.ps1`

3. **Validation**
   - `python test/test_azure_deployment.py`

### Utilisation quotidienne

- **Vérifier l'état** : `azure-manage status`
- **Voir les logs** : `azure-manage logs`
- **Redémarrer** : `azure-manage restart`
- **Tester** : `python test/test_azure_deployment.py`

## 🔍 Dépannage

### Problèmes courants

1. **Serveur inaccessible**
   - Vérifier l'état : `azure-manage status`
   - Consulter les logs : `azure-manage logs`

2. **Authentification échouée**
   - Vérifier les variables Azure AD dans `.env`
   - Tester le token : `azure-get-token.ps1`

3. **Container qui redémarre**
   - Problème de configuration réseau (HOST=0.0.0.0)
   - Dépendances manquantes (FastAPI, uvicorn)

### Support

- 📖 Documentation complète : `README_TESTS.md`
- 🐧 Guide Linux : `deploiement/README_LINUX.md`
- 🧪 Tests : Dossier `test/`

## 📝 Licence

MIT License - Voir le fichier LICENSE pour plus de détails.

## 🤝 Contribution

Les contributions sont les bienvenues ! Merci de :
1. Fork le projet
2. Créer une branche feature
3. Commit vos changements
4. Push vers la branche
5. Ouvrir une Pull Request

---

**🌤️ MCP Weather Server - Météo intelligente avec Azure AD et déploiement cloud !**
