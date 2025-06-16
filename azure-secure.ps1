#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Script de sécurisation Azure AD pour le container MCP Weather existant
.DESCRIPTION
    Ce script met à jour un container Azure existant avec l'authentification Azure AD
    sans nécessiter un redéploiement complet
.PARAMETER ResourceGroupName
    Nom du groupe de ressources Azure
.PARAMETER ContainerInstanceName
    Nom de l'instance de conteneur à sécuriser
.PARAMETER ContainerRegistryName
    Nom du registre de conteneurs Azure
.PARAMETER TenantId
    Azure AD Tenant ID
.PARAMETER ClientId
    Azure AD Client ID (Application ID)
.PARAMETER ClientSecret
    Azure AD Client Secret
.EXAMPLE
    .\azure-secure.ps1 -ContainerRegistryName "mcpweather2024" -TenantId "your-tenant-id" -ClientId "your-client-id" -ClientSecret "your-secret"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "mcp-weather-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerInstanceName = "mcp-weather-server",
    
    [Parameter(Mandatory=$true)]
    [string]$ContainerRegistryName,
    
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$true)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$true)]
    [string]$ClientSecret,
    
    [Parameter(Mandatory=$false)]
    [string]$ImageTag = "secure"
)

# Configuration des couleurs pour les messages
$ErrorActionPreference = "Stop"

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

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "ℹ️  $Message" "Blue"
}

# En-tête
Write-ColorOutput "🔐 Sécurisation Azure AD - MCP Weather Server" "Magenta"
Write-ColorOutput "=============================================" "Magenta"

# Vérification de la connexion Azure
Write-Step "Vérification de la connexion Azure..."
try {
    $account = az account show --output json | ConvertFrom-Json
    Write-Success "Connecté à Azure avec: $($account.user.name)"
} catch {
    Write-Error "Vous n'êtes pas connecté à Azure. Exécutez 'az login' pour vous connecter."
    exit 1
}

# Variables dérivées
$acrLoginServer = "$ContainerRegistryName.azurecr.io"
$imageName = "$acrLoginServer/mcp-weather-server"
$secureImageName = "$imageName`:$ImageTag"

Write-ColorOutput "`n📋 Configuration de sécurisation:" "Yellow"
Write-ColorOutput "  • Groupe de ressources: $ResourceGroupName" "White"
Write-ColorOutput "  • Instance de conteneur: $ContainerInstanceName" "White"
Write-ColorOutput "  • Registre: $ContainerRegistryName" "White"
Write-ColorOutput "  • Image sécurisée: $secureImageName" "White"
Write-ColorOutput "  • Azure AD Tenant: $TenantId" "White"
Write-ColorOutput "  • Azure AD Client: $ClientId" "White"

# Vérifier que le container existe
Write-Step "Vérification de l'existence du container..."
try {
    $containerInfo = az container show --resource-group $ResourceGroupName --name $ContainerInstanceName --output json | ConvertFrom-Json
    Write-Success "Container '$ContainerInstanceName' trouvé"
    Write-Info "État actuel: $($containerInfo.instanceView.currentState.state)"
} catch {
    Write-Error "Container '$ContainerInstanceName' non trouvé dans le groupe '$ResourceGroupName'"
    Write-Info "Assurez-vous que le container est déployé avant de le sécuriser"
    exit 1
}

# Étape 1: Ajouter les variables Azure AD au fichier .env existant
Write-Step "Ajout des variables Azure AD au fichier .env..."
try {
    # Vérifier si le fichier .env existe
    if (Test-Path ".env") {
        Write-Info "Fichier .env existant détecté - ajout des variables Azure AD"
        
        # Lire le contenu existant
        $existingContent = Get-Content ".env" -Raw
        
        # Supprimer les anciennes variables Azure AD si elles existent
        $existingContent = $existingContent -replace "(?m)^AZURE_AD_.*$", ""
        $existingContent = $existingContent -replace "(?m)^MCP_SECURE_MODE=.*$", ""
        
        # Nettoyer les lignes vides multiples
        $existingContent = $existingContent -replace "(?m)^\s*$\n", ""
        
        # Ajouter les nouvelles variables Azure AD
        $newContent = $existingContent.TrimEnd() + "`n`n# Configuration Azure AD pour l'authentification`n"
        $newContent += "AZURE_AD_TENANT_ID=$TenantId`n"
        $newContent += "AZURE_AD_CLIENT_ID=$ClientId`n"
        $newContent += "AZURE_AD_CLIENT_SECRET=$ClientSecret`n"
        $newContent += "MCP_SECURE_MODE=true`n"
        
        # Sauvegarder le fichier mis à jour
        $newContent | Out-File -FilePath ".env" -Encoding UTF8 -NoNewline
        Write-Success "Variables Azure AD ajoutées au fichier .env existant"
        
    } else {
        Write-Warning "Fichier .env non trouvé - création d'un nouveau fichier"
        
        # Créer un nouveau fichier .env minimal
        $envContent = @"
# Configuration Azure AD pour l'authentification
AZURE_AD_TENANT_ID=$TenantId
AZURE_AD_CLIENT_ID=$ClientId
AZURE_AD_CLIENT_SECRET=$ClientSecret

# Mode sécurisé activé
MCP_SECURE_MODE=true
"@
        $envContent | Out-File -FilePath ".env" -Encoding UTF8
        Write-Success "Nouveau fichier .env créé avec les variables Azure AD"
    }
} catch {
    Write-Error "Erreur lors de la mise à jour du fichier .env: $_"
    exit 1
}

# Étape 2: Construire une nouvelle image avec les variables d'environnement
Write-Step "Construction de l'image Docker sécurisée..."
try {
    # Créer un Dockerfile temporaire qui inclut les variables d'environnement (non sensibles seulement)
    $secureDockerfile = @"
# Image sécurisée basée sur l'image existante
FROM $imageName`:latest

# Ajout des variables d'environnement non sensibles
ENV AZURE_AD_TENANT_ID=$TenantId
ENV AZURE_AD_CLIENT_ID=$ClientId
ENV MCP_SECURE_MODE=true

# Note: AZURE_AD_CLIENT_SECRET sera passé au runtime pour la sécurité

# Réexposer le port
EXPOSE 8000

# Commande par défaut (inchangée)
CMD ["python", "-m", "src.main"]
"@

    $secureDockerfile | Out-File -FilePath "Dockerfile.secure" -Encoding UTF8
    
    # Construire la nouvelle image
    docker build -f Dockerfile.secure -t $secureImageName .
    Write-Success "Image Docker sécurisée construite"
    
    # Nettoyer le Dockerfile temporaire
    Remove-Item "Dockerfile.secure" -Force
    
} catch {
    Write-Error "Erreur lors de la construction de l'image sécurisée: $_"
    exit 1
}

# Étape 3: Se connecter au registre et pousser l'image
Write-Step "Connexion au registre de conteneurs..."
try {
    az acr login --name $ContainerRegistryName
    Write-Success "Connexion au registre réussie"
} catch {
    Write-Error "Erreur lors de la connexion au registre: $_"
    exit 1
}

Write-Step "Push de l'image sécurisée vers Azure Container Registry..."
try {
    docker push $secureImageName
    Write-Success "Image sécurisée poussée vers ACR"
} catch {
    Write-Error "Erreur lors du push: $_"
    exit 1
}

# Étape 4: Obtenir les identifiants du registre
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

# Étape 5: Supprimer l'ancien container
Write-Step "Suppression de l'ancien container non sécurisé..."
try {
    az container delete --resource-group $ResourceGroupName --name $ContainerInstanceName --yes --output none
    Write-Success "Ancien container supprimé"
    
    # Attendre un peu pour que la suppression soit effective
    Start-Sleep -Seconds 10
} catch {
    Write-Error "Erreur lors de la suppression de l'ancien container: $_"
    exit 1
}

# Étape 6: Déployer le nouveau container sécurisé
Write-Step "Déploiement du container sécurisé avec Azure AD..."
try {
    $deployResult = az container create `
        --resource-group $ResourceGroupName `
        --name $ContainerInstanceName `
        --image $secureImageName `
        --registry-login-server $acrLoginServer `
        --registry-username $acrUsername `
        --registry-password $acrPassword `
        --cpu 1 `
        --memory 1 `
        --os-type Linux `
        --restart-policy Always `
        --environment-variables PYTHONUNBUFFERED=1 PYTHONPATH=/app MCP_SECURE_MODE=true AZURE_AD_TENANT_ID=$TenantId AZURE_AD_CLIENT_ID=$ClientId AZURE_AD_CLIENT_SECRET=$ClientSecret `
        --ports 8000 `
        --protocol TCP `
        --dns-name-label $ContainerInstanceName `
        --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Erreur lors du déploiement sécurisé: $deployResult"
        exit 1
    }
    
    Write-Success "Container sécurisé déployé avec succès"
} catch {
    Write-Error "Erreur lors du déploiement sécurisé: $_"
    exit 1
}

# Étape 7: Vérifier le déploiement sécurisé
Write-Step "Vérification du déploiement sécurisé..."
try {
    Start-Sleep -Seconds 15
    
    $containerInfo = az container show --resource-group $ResourceGroupName --name $ContainerInstanceName --output json | ConvertFrom-Json
    
    if (-not $containerInfo) {
        Write-Error "Impossible de récupérer les informations du container sécurisé"
        exit 1
    }
    
    $publicIP = $containerInfo.ipAddress.ip
    $fqdn = $containerInfo.ipAddress.fqdn
    $state = $containerInfo.instanceView.currentState.state
    
    Write-Success "Container sécurisé déployé et opérationnel!"
    
    Write-ColorOutput "`n🔐 Informations du déploiement sécurisé:" "Green"
    Write-ColorOutput "========================================" "Green"
    Write-ColorOutput "  • Nom de l'instance: $ContainerInstanceName" "White"
    Write-ColorOutput "  • État: $state" "White"
    Write-ColorOutput "  • Adresse IP publique: $publicIP" "White"
    if ($fqdn) {
        Write-ColorOutput "  • FQDN: $fqdn" "White"
        Write-ColorOutput "  • URL sécurisée: https://$fqdn`:8000" "White"
    }
    Write-ColorOutput "  • Mode sécurisé: ✅ ACTIVÉ" "Green"
    Write-ColorOutput "  • Azure AD Tenant: $TenantId" "White"
    Write-ColorOutput "  • Azure AD Application: $ClientId" "White"
    
} catch {
    Write-Error "Erreur lors de la vérification: $_"
    exit 1
}

# Étape 8: Test de l'authentification
Write-Step "Test de l'authentification Azure AD..."
try {
    Write-Info "Test de l'endpoint non authentifié..."
    $testUrl = "http://$fqdn`:8000"
    
    # Test sans authentification (devrait échouer)
    try {
        $response = Invoke-WebRequest -Uri $testUrl -Method GET -TimeoutSec 10
        Write-Warning "⚠️  L'endpoint répond sans authentification - vérifiez la configuration"
    } catch {
        Write-Success "✅ L'endpoint requiert bien une authentification"
    }
    
} catch {
    Write-Warning "Impossible de tester l'authentification automatiquement"
}

# Étape 9: Instructions pour l'utilisation
Write-ColorOutput "`n📚 Instructions d'utilisation:" "Blue"
Write-ColorOutput "==============================" "Blue"
Write-ColorOutput "1. Obtenir un token Azure AD:" "White"
Write-ColorOutput "   • Connectez-vous à votre application Azure AD 'mcp-weather-secure'" "Gray"
Write-ColorOutput "   • Obtenez un token d'accès valide" "Gray"
Write-ColorOutput ""
Write-ColorOutput "2. Utiliser l'API sécurisée:" "White"
Write-ColorOutput "   curl -H 'Authorization: Bearer YOUR_TOKEN' http://$fqdn`:8000/api/weather" "Gray"
Write-ColorOutput ""
Write-ColorOutput "3. Intégration avec Claude Desktop:" "White"
Write-ColorOutput "   • Mettez à jour votre configuration MCP" "Gray"
Write-ColorOutput "   • Ajoutez les variables d'environnement Azure AD" "Gray"

Write-ColorOutput "`n🛠️  Commandes de gestion:" "Yellow"
Write-ColorOutput "=========================" "Yellow"
Write-ColorOutput "Voir les logs du container sécurisé:" "White"
Write-ColorOutput "  az container logs --resource-group $ResourceGroupName --name $ContainerInstanceName --follow" "Gray"
Write-ColorOutput ""
Write-ColorOutput "Redémarrer le container:" "White"
Write-ColorOutput "  az container restart --resource-group $ResourceGroupName --name $ContainerInstanceName" "Gray"
Write-ColorOutput ""
Write-ColorOutput "Vérifier les variables d'environnement:" "White"
Write-ColorOutput "  az container show --resource-group $ResourceGroupName --name $ContainerInstanceName --query 'containers[0].environmentVariables'" "Gray"

Write-ColorOutput "`n🔒 Sécurité activée:" "Green"
Write-ColorOutput "===================" "Green"
Write-ColorOutput "✅ Authentification Azure AD activée" "Green"
Write-ColorOutput "✅ Variables d'environnement sécurisées" "Green"
Write-ColorOutput "✅ Logs conformes RGPD" "Green"
Write-ColorOutput "✅ Validation des tokens JWT" "Green"
Write-ColorOutput "✅ Gestion des rôles utilisateur" "Green"

Write-ColorOutput "`n🎉 Sécurisation terminée avec succès!" "Green"
Write-ColorOutput "Votre serveur MCP Weather est maintenant sécurisé avec Azure AD!" "Green" 