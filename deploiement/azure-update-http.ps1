#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Met à jour le déploiement Azure pour utiliser le serveur HTTP
.DESCRIPTION
    Ce script met à jour le container Azure existant pour utiliser le serveur HTTP
    au lieu du serveur stdio, permettant les tests via HTTP/REST.
#>

param(
    [string]$ResourceGroup = "mcp-weather-rg",
    [string]$ContainerName = "mcp-weather-server",
    [string]$RegistryName = "mcpweatheracr3590",
    [string]$ImageTag = "http"
)

# Configuration
$ErrorActionPreference = "Stop"

Write-Host "🔄 MISE À JOUR DÉPLOIEMENT AZURE VERS HTTP" -ForegroundColor Cyan
Write-Host "=" * 50

# Vérifier Azure CLI
try {
    $azVersion = az version --query '"azure-cli"' -o tsv
    Write-Host "✅ Azure CLI version: $azVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Azure CLI non trouvé" -ForegroundColor Red
    exit 1
}

# Vérifier la connexion Azure
try {
    $account = az account show --query "name" -o tsv
    Write-Host "✅ Connecté à Azure: $account" -ForegroundColor Green
} catch {
    Write-Host "❌ Non connecté à Azure" -ForegroundColor Red
    Write-Host "💡 Connectez-vous avec: az login" -ForegroundColor Yellow
    exit 1
}

# Vérifier si le container existe
Write-Host "🔍 Vérification du container existant..." -ForegroundColor Yellow
try {
    $containerState = az container show --resource-group $ResourceGroup --name $ContainerName --query "instanceView.state" -o tsv
    Write-Host "✅ Container trouvé (État: $containerState)" -ForegroundColor Green
} catch {
    Write-Host "❌ Container non trouvé" -ForegroundColor Red
    exit 1
}

# Construire la nouvelle image HTTP
Write-Host "🔨 Construction de l'image HTTP..." -ForegroundColor Yellow
try {
    Write-Host "   📄 Utilisation de Dockerfile.http"
    
    # Vérifier si Dockerfile.http existe
    if (-not (Test-Path "Dockerfile.http")) {
        Write-Host "❌ Dockerfile.http non trouvé" -ForegroundColor Red
        exit 1
    }
    
    # Construire l'image dans Azure Container Registry
    az acr build --registry $RegistryName --image "mcp-weather-server:$ImageTag" --file Dockerfile.http .
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Image HTTP construite avec succès" -ForegroundColor Green
    } else {
        Write-Host "❌ Échec de construction de l'image" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Erreur lors de la construction: $_" -ForegroundColor Red
    exit 1
}

# Arrêter le container existant
Write-Host "🛑 Arrêt du container existant..." -ForegroundColor Yellow
try {
    az container stop --resource-group $ResourceGroup --name $ContainerName
    Write-Host "✅ Container arrêté" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Erreur lors de l'arrêt (peut être déjà arrêté)" -ForegroundColor Yellow
}

# Supprimer le container existant
Write-Host "🗑️ Suppression du container existant..." -ForegroundColor Yellow
try {
    az container delete --resource-group $ResourceGroup --name $ContainerName --yes
    Write-Host "✅ Container supprimé" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Erreur lors de la suppression" -ForegroundColor Yellow
}

# Attendre un peu
Write-Host "⏳ Attente 10 secondes..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Redéployer avec la nouvelle image HTTP
Write-Host "🚀 Redéploiement avec serveur HTTP..." -ForegroundColor Yellow

# Récupérer les variables d'environnement du fichier .env
$envVars = @()
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^([^#][^=]+)=(.+)$") {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            
            # Ajouter seulement les variables nécessaires
            if ($name -in @("OPENWEATHER_API_KEY", "AZURE_AD_TENANT_ID", "AZURE_AD_CLIENT_ID", "AZURE_AD_CLIENT_SECRET")) {
                $envVars += "$name=$value"
            }
        }
    }
}

if ($envVars.Count -eq 0) {
    Write-Host "⚠️ Aucune variable d'environnement trouvée dans .env" -ForegroundColor Yellow
}

# Construire la commande de déploiement
$deployCmd = @(
    "az", "container", "create",
    "--resource-group", $ResourceGroup,
    "--name", $ContainerName,
    "--image", "$RegistryName.azurecr.io/mcp-weather-server:$ImageTag",
    "--registry-login-server", "$RegistryName.azurecr.io",
    "--registry-username", $RegistryName,
    "--registry-password", (az acr credential show --name $RegistryName --query "passwords[0].value" -o tsv),
    "--dns-name-label", $ContainerName,
    "--ports", "8000",
    "--protocol", "TCP",
    "--os-type", "Linux",
    "--cpu", "1",
    "--memory", "1.5"
)

# Ajouter les variables d'environnement
foreach ($envVar in $envVars) {
    $deployCmd += "--environment-variables"
    $deployCmd += $envVar
}

try {
    Write-Host "   🔧 Déploiement en cours..."
    & $deployCmd[0] $deployCmd[1..($deployCmd.Length-1)]
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Container redéployé avec succès" -ForegroundColor Green
    } else {
        Write-Host "❌ Échec du redéploiement" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Erreur lors du redéploiement: $_" -ForegroundColor Red
    exit 1
}

# Attendre que le container soit prêt
Write-Host "⏳ Attente du démarrage du container..." -ForegroundColor Yellow
$maxAttempts = 12
$attempt = 0

do {
    Start-Sleep -Seconds 10
    $attempt++
    
    try {
        $state = az container show --resource-group $ResourceGroup --name $ContainerName --query "instanceView.state" -o tsv
        Write-Host "   Tentative $attempt/$maxAttempts - État: $state"
        
        if ($state -eq "Running") {
            break
        }
    } catch {
        Write-Host "   Tentative $attempt/$maxAttempts - Vérification..."
    }
} while ($attempt -lt $maxAttempts)

if ($attempt -ge $maxAttempts) {
    Write-Host "⚠️ Timeout - vérifiez manuellement l'état du container" -ForegroundColor Yellow
} else {
    Write-Host "✅ Container en cours d'exécution" -ForegroundColor Green
}

# Afficher les informations de connexion
Write-Host "`n📋 INFORMATIONS DE CONNEXION" -ForegroundColor Cyan
Write-Host "=" * 40

try {
    $containerInfo = az container show --resource-group $ResourceGroup --name $ContainerName --query "{fqdn: ipAddress.fqdn, ip: ipAddress.ip, state: instanceView.state}" -o json | ConvertFrom-Json
    
    $url = "https://$($containerInfo.fqdn):8000"
    
    Write-Host "🌐 URL du serveur: $url" -ForegroundColor Green
    Write-Host "🔗 Health check: $url/health" -ForegroundColor Green
    Write-Host "🛠️ API MCP: $url/mcp" -ForegroundColor Green
    Write-Host "📊 État: $($containerInfo.state)" -ForegroundColor Green
    
    # Mettre à jour le fichier .env avec la nouvelle URL
    if (Test-Path ".env") {
        $envContent = Get-Content ".env"
        $newEnvContent = @()
        $urlUpdated = $false
        
        foreach ($line in $envContent) {
            if ($line -match "^AZURE_SERVER_URL=") {
                $newEnvContent += "AZURE_SERVER_URL=$url"
                $urlUpdated = $true
            } else {
                $newEnvContent += $line
            }
        }
        
        if (-not $urlUpdated) {
            $newEnvContent += "AZURE_SERVER_URL=$url"
        }
        
        $newEnvContent | Set-Content ".env"
        Write-Host "✅ Fichier .env mis à jour avec la nouvelle URL" -ForegroundColor Green
    }
    
} catch {
    Write-Host "⚠️ Impossible de récupérer les informations du container" -ForegroundColor Yellow
}

# Test de connectivité
Write-Host "`n🧪 TEST DE CONNECTIVITÉ" -ForegroundColor Cyan
Write-Host "=" * 30

try {
    $healthUrl = "https://$($containerInfo.fqdn):8000/health"
    Write-Host "🔍 Test de $healthUrl..."
    
    # Attendre un peu plus pour que le serveur soit prêt
    Start-Sleep -Seconds 5
    
    $response = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 10
    
    if ($response.status -eq "healthy") {
        Write-Host "✅ Serveur HTTP accessible et fonctionnel!" -ForegroundColor Green
        Write-Host "🎉 Mise à jour réussie - vous pouvez maintenant tester avec:" -ForegroundColor Green
        Write-Host "   python test/test_azure_deployment.py" -ForegroundColor Yellow
    } else {
        Write-Host "⚠️ Serveur accessible mais réponse inattendue" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️ Test de connectivité échoué: $_" -ForegroundColor Yellow
    Write-Host "💡 Le serveur peut encore être en cours de démarrage" -ForegroundColor Yellow
    Write-Host "   Réessayez dans quelques minutes avec:" -ForegroundColor Yellow
    Write-Host "   python test/test_azure_deployment.py" -ForegroundColor Yellow
}

Write-Host "`n🎉 MISE À JOUR TERMINÉE!" -ForegroundColor Green
Write-Host "Le serveur Azure utilise maintenant le mode HTTP et peut être testé." -ForegroundColor Green 