#!/usr/bin/env pwsh
# Script de sécurisation Azure AD pour MCP Weather Server
# Ajoute l'authentification Azure AD au conteneur existant

param(
    [string]$ResourceGroup = "mcp-weather-rg",
    [string]$ContainerName = "mcp-weather-server",
    [switch]$Force
)

# Configuration des couleurs pour les messages
$Colors = @{
    Success = "Green"
    Warning = "Yellow" 
    Error = "Red"
    Info = "Cyan"
    Header = "Magenta"
}

function Write-ColorMessage {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Colors[$Color]
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-ColorMessage "=" * 50 -Color "Header"
    Write-ColorMessage $Title -Color "Header"
    Write-ColorMessage "=" * 50 -Color "Header"
}

function Get-AzureADVariables {
    Write-Header "VÉRIFICATION DES VARIABLES AZURE AD"
    
    # Lire les variables depuis le fichier .env
    $envVars = @{}
    if (Test-Path ".env") {
        $envContent = Get-Content ".env" | Where-Object { $_ -match "^[^#].*=" }
        foreach ($line in $envContent) {
            $parts = $line.Split('=', 2)
            if ($parts.Length -eq 2) {
                $key = $parts[0].Trim()
                $value = $parts[1].Trim().Trim('"')
                $envVars[$key] = $value
            }
        }
    }
    
    # Vérifier les variables Azure AD requises
    $requiredVars = @("AZURE_AD_TENANT_ID", "AZURE_AD_CLIENT_ID", "AZURE_AD_CLIENT_SECRET")
    $missingVars = @()
    
    foreach ($var in $requiredVars) {
        if (-not $envVars.ContainsKey($var) -or [string]::IsNullOrWhiteSpace($envVars[$var])) {
            $missingVars += $var
        } else {
            Write-ColorMessage "✅ $var configuré" -Color "Success"
        }
    }
    
    if ($missingVars.Count -gt 0) {
        Write-ColorMessage "❌ Variables Azure AD manquantes: $($missingVars -join ', ')" -Color "Error"
        Write-ColorMessage "💡 Ajoutez ces variables dans votre fichier .env" -Color "Info"
        return $null
    }
    
    return $envVars
}

function Get-ContainerInfo {
    Write-Header "RÉCUPÉRATION DES INFORMATIONS DU CONTENEUR"
    
    try {
        $container = az container show --resource-group $ResourceGroup --name $ContainerName --output json | ConvertFrom-Json
        
        Write-ColorMessage "✅ Conteneur trouvé: $($container.name)" -Color "Success"
        Write-ColorMessage "   • État: $($container.instanceView.state)" -Color "Info"
        Write-ColorMessage "   • Image: $($container.containers[0].image)" -Color "Info"
        Write-ColorMessage "   • URL: http://$($container.ipAddress.fqdn):8000" -Color "Info"
        
        return $container
        
    } catch {
        Write-ColorMessage "❌ Conteneur '$ContainerName' non trouvé dans '$ResourceGroup'" -Color "Error"
        return $null
    }
}

function Update-ContainerWithAuth {
    param($Container, $EnvVars)
    
    Write-Header "MISE À JOUR DU CONTENEUR AVEC AZURE AD"
    
    # Extraire les informations nécessaires
    $imageName = $Container.containers[0].image
    $registryServer = $imageName.Split('/')[0]
    $dnsLabel = $Container.ipAddress.dnsNameLabel
    
    Write-ColorMessage "🔧 Suppression du conteneur existant..." -Color "Info"
    az container delete --resource-group $ResourceGroup --name $ContainerName --yes --output none
    
    if ($LASTEXITCODE -ne 0) {
        Write-ColorMessage "❌ Échec de la suppression du conteneur" -Color "Error"
        return $false
    }
    
    Write-ColorMessage "✅ Conteneur supprimé" -Color "Success"
    
    # Préparer les variables d'environnement avec Azure AD
    $allEnvVars = @()
    
    # Variables de base
    $allEnvVars += "PORT=8000"
    $allEnvVars += "HOST=0.0.0.0"
    $allEnvVars += "ENVIRONMENT=production"
    $allEnvVars += "LOG_LEVEL=INFO"
    
    # Variables Azure AD
    $allEnvVars += "AZURE_AD_TENANT_ID=$($EnvVars['AZURE_AD_TENANT_ID'])"
    $allEnvVars += "AZURE_AD_CLIENT_ID=$($EnvVars['AZURE_AD_CLIENT_ID'])"
    $allEnvVars += "AZURE_AD_CLIENT_SECRET=$($EnvVars['AZURE_AD_CLIENT_SECRET'])"
    
    # Mode sécurisé
    $allEnvVars += "MCP_SECURE_MODE=true"
    
    Write-ColorMessage "🔧 Recréation du conteneur avec authentification Azure AD..." -Color "Info"
    Write-ColorMessage "🔑 Mode sécurisé activé" -Color "Warning"
    
    # Obtenir les credentials du registre
    $registryNameOnly = $registryServer.Split('.')[0]
    $credentials = az acr credential show --name $registryNameOnly --output json | ConvertFrom-Json
    
    # Recréer le conteneur avec l'authentification
    $deployCmd = @(
        "az", "container", "create",
        "--resource-group", $ResourceGroup,
        "--name", $ContainerName,
        "--image", $imageName,
        "--cpu", "1",
        "--memory", "1.5",
        "--registry-login-server", $registryServer,
        "--registry-username", $credentials.username,
        "--registry-password", $credentials.passwords[0].value,
        "--ports", "8000",
        "--protocol", "TCP",
        "--os-type", "Linux",
        "--dns-name-label", $dnsLabel,
        "--environment-variables"
    )
    
    $deployCmd += $allEnvVars
    $deployCmd += "--output"
    $deployCmd += "json"
    
    $result = & $deployCmd[0] @($deployCmd[1..($deployCmd.Length-1)])
    
    if ($LASTEXITCODE -eq 0) {
        $newContainer = $result | ConvertFrom-Json
        Write-ColorMessage "✅ Conteneur sécurisé créé avec succès!" -Color "Success"
        Write-ColorMessage "🌐 URL: http://$($newContainer.ipAddress.fqdn):8000" -Color "Success"
        Write-ColorMessage "🔐 Authentification Azure AD: ACTIVÉE" -Color "Success"
        return $true
    }
    else {
        Write-ColorMessage "❌ Échec de la création du conteneur sécurisé" -Color "Error"
        return $false
    }
}

function Test-SecuredDeployment {
    Write-Header "TEST DU DÉPLOIEMENT SÉCURISÉ"
    
    Write-ColorMessage "⏳ Attente du démarrage du conteneur (30 secondes)..." -Color "Info"
    Start-Sleep -Seconds 30
    
    Write-ColorMessage "🧪 Lancement des tests de sécurité..." -Color "Info"
    
    # Lancer le test de déploiement Azure
    try {
        $env:AZURE_SERVER_URL = "http://mcp-weather-202506171227.francecentral.azurecontainer.io:8000"
        python test/test_azure_deployment.py
    }
    catch {
        Write-ColorMessage "⚠️ Erreur lors du test: $($_.Exception.Message)" -Color "Warning"
    }
}

# SCRIPT PRINCIPAL
try {
    Write-Header "🔐 SÉCURISATION MCP WEATHER SERVER AVEC AZURE AD"
    
    # Vérifier la connexion Azure
    try {
        $account = az account show --output json | ConvertFrom-Json
        Write-ColorMessage "✅ Connecté à Azure (Subscription: $($account.name))" -Color "Success"
    }
    catch {
        Write-ColorMessage "❌ Non connecté à Azure. Exécutez 'az login' d'abord." -Color "Error"
        exit 1
    }
    
    # Étape 1: Vérifier les variables Azure AD
    $envVars = Get-AzureADVariables
    if (-not $envVars) {
        exit 1
    }
    
    # Étape 2: Récupérer les informations du conteneur
    $container = Get-ContainerInfo
    if (-not $container) {
        exit 1
    }
    
    # Étape 3: Confirmation
    if (-not $Force) {
        Write-ColorMessage "⚠️ ATTENTION: Cette opération va:" -Color "Warning"
        Write-ColorMessage "   • Supprimer le conteneur existant" -Color "Warning"
        Write-ColorMessage "   • Recréer le conteneur avec authentification Azure AD" -Color "Warning"
        Write-ColorMessage "   • Activer le mode sécurisé" -Color "Warning"
        
        $confirmation = Read-Host "Continuer? (o/N)"
        if ($confirmation -ne "o" -and $confirmation -ne "O") {
            Write-ColorMessage "❌ Opération annulée" -Color "Info"
            exit 0
        }
    }
    
    # Étape 4: Mise à jour avec authentification
    $success = Update-ContainerWithAuth -Container $container -EnvVars $envVars
    
    if ($success) {
        # Étape 5: Test du déploiement sécurisé
        Test-SecuredDeployment
        
        Write-ColorMessage "🎉 Sécurisation terminée avec succès!" -Color "Success"
        Write-ColorMessage "🔐 Le serveur MCP Weather est maintenant sécurisé avec Azure AD" -Color "Success"
    }
    else {
        Write-ColorMessage "❌ Échec de la sécurisation" -Color "Error"
        exit 1
    }
}
catch {
    Write-ColorMessage "❌ Erreur durant la sécurisation: $($_.Exception.Message)" -Color "Error"
    exit 1
} 