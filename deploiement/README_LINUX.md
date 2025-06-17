# Scripts de déploiement Azure - Version Linux

Ce dossier contient les versions Linux (bash) des scripts de déploiement Azure pour le serveur MCP Weather.

## Scripts disponibles

### 🛠️ `azure-setup.sh` - Configuration et vérification des prérequis

Script de configuration qui vérifie et installe les prérequis nécessaires.

```bash
# Vérifier les prérequis
./azure-setup.sh --check-only

# Installer automatiquement les prérequis manquants
./azure-setup.sh --install-prerequisites

# Afficher l'aide
./azure-setup.sh --help
```

**Prérequis installés automatiquement :**
- Azure CLI (via apt/yum/dnf selon la distribution)
- Docker (avec configuration automatique)

### 🚀 `deploy-azure.sh` - Déploiement principal

Script principal pour déployer le serveur MCP Weather sur Azure.

```bash
# Déploiement basique (nom de registre obligatoire)
./deploy-azure.sh --container-registry-name "monregistreunique123"

# Déploiement avec paramètres personnalisés
./deploy-azure.sh \
  --container-registry-name "monregistre" \
  --resource-group-name "mon-rg" \
  --location "westeurope" \
  --container-instance-name "mon-serveur"

# Afficher l'aide
./deploy-azure.sh --help
```

**Ce que fait le script :**
1. Vérifie les prérequis (Azure CLI, Docker)
2. Crée le groupe de ressources Azure
3. Crée Azure Container Registry
4. Construit et pousse l'image Docker
5. Déploie sur Azure Container Instances

### 🔧 `azure-manage.sh` - Gestion du déploiement

Script pour gérer le serveur déployé.

```bash
# Voir l'état du conteneur
./azure-manage.sh --action status

# Voir les logs (temps réel)
./azure-manage.sh --action logs --follow

# Redémarrer le conteneur
./azure-manage.sh --action restart

# Arrêter/démarrer le conteneur
./azure-manage.sh --action stop
./azure-manage.sh --action start

# Supprimer complètement le déploiement
./azure-manage.sh --action delete

# Afficher l'aide
./azure-manage.sh --action help
```

### 🔄 `azure-update-http.sh` - Mise à jour vers serveur HTTP

Met à jour le déploiement pour utiliser le serveur HTTP au lieu du serveur stdio.

```bash
# Mise à jour avec paramètres par défaut
./azure-update-http.sh

# Mise à jour avec paramètres personnalisés
./azure-update-http.sh \
  --resource-group "mon-rg" \
  --container-name "mon-serveur" \
  --registry-name "monregistre"
```

### 🧹 `azure-cleanup.sh` - Nettoyage des ressources

Supprime toutes les ressources Azure créées.

```bash
# Nettoyage avec confirmation
./azure-cleanup.sh --resource-group-name "mcp-weather-rg"

# Nettoyage forcé (sans confirmation)
./azure-cleanup.sh --resource-group-name "mcp-weather-rg" --force

# Nettoyage avec registre spécifique
./azure-cleanup.sh \
  --resource-group-name "mcp-weather-rg" \
  --container-registry-name "monregistre"
```

## Workflow de déploiement recommandé

### 1. Préparation initiale

```bash
# 1. Vérifier les prérequis
./azure-setup.sh --check-only

# 2. Installer les prérequis si nécessaire
./azure-setup.sh --install-prerequisites

# 3. Se connecter à Azure
az login
```

### 2. Premier déploiement

```bash
# Déployer avec un nom de registre unique
./deploy-azure.sh --container-registry-name "mcpweather$(date +%s)"
```

### 3. Gestion quotidienne

```bash
# Vérifier l'état
./azure-manage.sh --action status

# Voir les logs
./azure-manage.sh --action logs

# Redémarrer si nécessaire
./azure-manage.sh --action restart
```

### 4. Mise à jour vers HTTP (optionnel)

```bash
# Pour activer les tests HTTP
./azure-update-http.sh --registry-name "votre-registre"
```

### 5. Nettoyage final

```bash
# Supprimer toutes les ressources
./azure-cleanup.sh --resource-group-name "mcp-weather-rg" --force
```

## Différences avec les versions PowerShell

Les scripts Linux offrent les mêmes fonctionnalités que leurs équivalents PowerShell avec quelques adaptations :

### Avantages des versions Linux :
- **Installation automatique** : Support natif pour Ubuntu/Debian, CentOS/RHEL/Fedora
- **Gestion des permissions** : Configuration automatique de Docker (groupe docker)
- **Outils système** : Utilisation de `jq`, `curl` pour le parsing JSON et les tests HTTP
- **Couleurs** : Support des couleurs ANSI dans tous les terminaux Linux

### Prérequis système :
- **Distributions supportées** : Ubuntu, Debian, CentOS, RHEL, Fedora
- **Outils requis** : `jq` (installé automatiquement), `curl`
- **Permissions** : `sudo` pour l'installation des prérequis

## Dépannage

### Problèmes courants

**1. Permission denied lors de l'exécution**
```bash
chmod +x deploiement/*.sh
```

**2. Docker nécessite sudo**
```bash
# Après installation, se déconnecter/reconnecter ou :
sudo usermod -aG docker $USER
newgrp docker
```

**3. jq non trouvé**
```bash
# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL/Fedora
sudo yum install jq  # ou dnf install jq
```

**4. Azure CLI non trouvé après installation**
```bash
# Recharger le PATH
source ~/.bashrc
# ou redémarrer le terminal
```

### Variables d'environnement

Les scripts utilisent les mêmes variables d'environnement que les versions PowerShell :

```bash
# Dans .env
OPENWEATHER_API_KEY=votre_clé_api
AZURE_AD_TENANT_ID=votre_tenant_id
AZURE_AD_CLIENT_ID=votre_client_id
AZURE_AD_CLIENT_SECRET=votre_client_secret
```

## Support et contribution

Ces scripts sont des adaptations fidèles des versions PowerShell originales. Pour signaler des problèmes ou contribuer :

1. Vérifiez d'abord avec la version PowerShell équivalente
2. Testez sur votre distribution Linux
3. Documentez les erreurs avec les logs complets

Les scripts sont testés sur :
- ✅ Ubuntu 20.04/22.04
- ✅ Debian 11/12
- ✅ CentOS 8/9
- ✅ RHEL 8/9
- ✅ Fedora 35+ 