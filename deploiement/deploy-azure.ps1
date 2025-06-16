#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Script de déploiement Azure pour le serveur MCP Weather
.DESCRIPTION
    Ce script déploie automatiquement le serveur MCP Weather sur Azure Container Instances
    en utilisant Azure CLI et Azure Container Registry
.PARAMETER ResourceGroupName
    Nom du groupe de ressources Azure (par défaut: mcp-weather-rg)
.PARAMETER Location
    Région Azure pour le déploiement (par défaut: France Central)
.PARAMETER ContainerRegistryName
    Nom du registre de conteneurs Azure (doit être unique globalement)
.PARAMETER ContainerInstanceName
    Nom de l'instance de conteneur (par défaut: mcp-weather-server)
.EXAMPLE
    .\deploy-azure.ps1 -ContainerRegistryName "monregistreunique123"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "mcp-weather-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "francecentral",
    
    [Parameter(Mandatory=$true)]
    [string]$ContainerRegistryName,
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerInstanceName = "mcp-weather-server",
    
    [Parameter(Mandatory=$false)]
    [string]$ImageTag = "latest"
)

# Configuration des couleurs pour les messages
$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Step {
    param([string]$Message)
    Write-ColorOutput "🔄 $Message" "Cyan"
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "✅ $Message" "Green"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "❌ $Message" "Red"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "⚠️  $Message" "Yellow"
}

# Vérification des prérequis
Write-ColorOutput "🌤️  Déploiement du serveur MCP Weather sur Azure" "Magenta"
Write-ColorOutput "=================================================" "Magenta"

Write-Step "Vérification des prérequis..."

# Vérifier si Azure CLI est installé
try {
    $azVersion = az version --output json | ConvertFrom-Json
    Write-Success "Azure CLI version $($azVersion.'azure-cli') détecté"
} catch {
    Write-Error "Azure CLI n'est pas installé. Veuillez l'installer depuis https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}

# Vérifier si Docker est installé
try {
    $dockerVersion = docker --version
    Write-Success "Docker détecté: $dockerVersion"
} catch {
    Write-Error "Docker n'est pas installé. Veuillez l'installer depuis https://www.docker.com/products/docker-desktop"
    exit 1
}

# Vérifier si l'utilisateur est connecté à Azure
Write-Step "Vérification de la connexion Azure..."
try {
    $account = az account show --output json | ConvertFrom-Json
    Write-Success "Connecté à Azure avec le compte: $($account.user.name)"
    Write-ColorOutput "Abonnement actuel: $($account.name) ($($account.id))" "Yellow"
} catch {
    Write-Error "Vous n'êtes pas connecté à Azure. Exécutez 'az login' pour vous connecter."
    exit 1
}

# Demander confirmation pour continuer
$confirmation = Read-Host "Voulez-vous continuer avec cet abonnement? (o/N)"
if ($confirmation -ne "o" -and $confirmation -ne "O" -and $confirmation -ne "oui") {
    Write-Warning "Déploiement annulé par l'utilisateur."
    exit 0
}

# Variables dérivées
$acrLoginServer = "$ContainerRegistryName.azurecr.io"
$imageName = "$acrLoginServer/mcp-weather-server"
$imageFullName = "$imageName`:$ImageTag"

Write-ColorOutput "`n📋 Configuration du déploiement:" "Yellow"
Write-ColorOutput "  • Groupe de ressources: $ResourceGroupName" "White"
Write-ColorOutput "  • Région: $Location" "White"
Write-ColorOutput "  • Registre de conteneurs: $ContainerRegistryName" "White"
Write-ColorOutput "  • Instance de conteneur: $ContainerInstanceName" "White"
Write-ColorOutput "  • Image: $imageFullName" "White"

# Étape 1: Créer le groupe de ressources
Write-Step "Création du groupe de ressources '$ResourceGroupName'..."
try {
    $rgExists = az group exists --name $ResourceGroupName --output tsv
    if ($rgExists -eq "true") {
        Write-Success "Le groupe de ressources '$ResourceGroupName' existe déjà"
    } else {
        az group create --name $ResourceGroupName --location $Location --output none
        Write-Success "Groupe de ressources '$ResourceGroupName' créé avec succès"
    }
} catch {
    Write-Error "Erreur lors de la création du groupe de ressources: $_"
    exit 1
}

# Étape 2: Créer Azure Container Registry
Write-Step "Création d'Azure Container Registry '$ContainerRegistryName'..."
try {
    $acrExists = az acr show --name $ContainerRegistryName --resource-group $ResourceGroupName --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Le registre de conteneurs '$ContainerRegistryName' existe déjà"
    } else {
        az acr create --resource-group $ResourceGroupName --name $ContainerRegistryName --sku Basic --admin-enabled true --output none
        Write-Success "Registre de conteneurs '$ContainerRegistryName' créé avec succès"
    }
} catch {
    Write-Error "Erreur lors de la création du registre de conteneurs: $_"
    exit 1
}

# Étape 3: Se connecter au registre de conteneurs
Write-Step "Connexion au registre de conteneurs..."
try {
    az acr login --name $ContainerRegistryName
    Write-Success "Connexion au registre de conteneurs réussie"
} catch {
    Write-Error "Erreur lors de la connexion au registre de conteneurs: $_"
    exit 1
}

# Étape 4: Construire et pousser l'image Docker
Write-Step "Construction de l'image Docker..."
try {
    # Vérifier que le Dockerfile existe
    if (-not (Test-Path "Dockerfile")) {
        Write-Error "Dockerfile non trouvé dans le répertoire courant"
        exit 1
    }
    
    docker build -t $imageName .
    Write-Success "Image Docker construite avec succès"
} catch {
    Write-Error "Erreur lors de la construction de l'image Docker: $_"
    exit 1
}

Write-Step "Ajout du tag et push vers Azure Container Registry..."
try {
    docker tag $imageName $imageFullName
    docker push $imageFullName
    Write-Success "Image poussée vers ACR avec succès"
} catch {
    Write-Error "Erreur lors du push vers ACR: $_"
    exit 1
}

# Étape 5: Obtenir les identifiants du registre
Write-Step "Récupération des identifiants du registre..."
try {
    $acrCredentials = az acr credential show --name $ContainerRegistryName --output json | ConvertFrom-Json
    $acrUsername = $acrCredentials.username
    $acrPassword = $acrCredentials.passwords[0].value
    Write-Success "Identifiants du registre récupérés"
} catch {
    Write-Error "Erreur lors de la récupération des identifiants: $_"
    exit 1
}

# Étape 6: Déployer sur Azure Container Instances
Write-Step "Déploiement sur Azure Container Instances..."
try {
    # Supprimer l'instance existante si elle existe
    $aciExists = az container show --resource-group $ResourceGroupName --name $ContainerInstanceName --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Warning "Instance de conteneur existante détectée. Suppression..."
        az container delete --resource-group $ResourceGroupName --name $ContainerInstanceName --yes --output none
        Write-Success "Instance existante supprimée"
    }
    
    # Créer la nouvelle instance
    $deployResult = az container create `
        --resource-group $ResourceGroupName `
        --name $ContainerInstanceName `
        --image $imageFullName `
        --registry-login-server $acrLoginServer `
        --registry-username $acrUsername `
        --registry-password $acrPassword `
        --cpu 1 `
        --memory 1 `
        --os-type Linux `
        --restart-policy Always `
        --environment-variables PYTHONUNBUFFERED=1 PYTHONPATH=/app `
        --ports 8000 `
        --protocol TCP `
        --dns-name-label $ContainerInstanceName `
        --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Erreur lors du déploiement: $deployResult"
        exit 1
    }
    
    Write-Success "Instance de conteneur déployée avec succès"
} catch {
    Write-Error "Erreur lors du déploiement sur ACI: $_"
    exit 1
}

# Étape 7: Obtenir les informations de déploiement
Write-Step "Récupération des informations de déploiement..."
try {
    # Attendre un peu que le conteneur soit complètement déployé
    Start-Sleep -Seconds 10
    
    $containerInfo = az container show --resource-group $ResourceGroupName --name $ContainerInstanceName --output json | ConvertFrom-Json
    
    if (-not $containerInfo) {
        Write-Error "Impossible de récupérer les informations du conteneur"
        exit 1
    }
    
    $publicIP = $containerInfo.ipAddress.ip
    $fqdn = $containerInfo.ipAddress.fqdn
    $state = $containerInfo.instanceView.currentState.state
    
    Write-Success "Déploiement terminé avec succès!"
    
    Write-ColorOutput "`n🎉 Informations de déploiement:" "Green"
    Write-ColorOutput "================================" "Green"
    Write-ColorOutput "  • Nom de l'instance: $ContainerInstanceName" "White"
    Write-ColorOutput "  • État: $state" "White"
    Write-ColorOutput "  • Adresse IP publique: $publicIP" "White"
    if ($fqdn) {
        Write-ColorOutput "  • FQDN: $fqdn" "White"
        Write-ColorOutput "  • URL d'accès: http://$fqdn`:8000" "White"
    }
    Write-ColorOutput "  • Groupe de ressources: $ResourceGroupName" "White"
    Write-ColorOutput "  • Registre de conteneurs: $acrLoginServer" "White"
    
} catch {
    Write-Error "Erreur lors de la récupération des informations: $_"
    exit 1
}

# Étape 8: Afficher les commandes utiles
Write-ColorOutput "`n🛠️  Commandes utiles:" "Yellow"
Write-ColorOutput "=====================" "Yellow"
Write-ColorOutput "Voir les logs:" "White"
Write-ColorOutput "  az container logs --resource-group $ResourceGroupName --name $ContainerInstanceName --follow" "Gray"
Write-ColorOutput "`nRedémarrer le conteneur:" "White"
Write-ColorOutput "  az container restart --resource-group $ResourceGroupName --name $ContainerInstanceName" "Gray"
Write-ColorOutput "`nSupprimer le déploiement:" "White"
Write-ColorOutput "  az group delete --name $ResourceGroupName --yes --no-wait" "Gray"
Write-ColorOutput "`nVoir l'état du conteneur:" "White"
Write-ColorOutput "  az container show --resource-group $ResourceGroupName --name $ContainerInstanceName --output table" "Gray"

Write-ColorOutput "`n✨ Déploiement terminé avec succès!" "Green"
Write-ColorOutput "Votre serveur MCP Weather est maintenant disponible sur Azure!" "Green" 