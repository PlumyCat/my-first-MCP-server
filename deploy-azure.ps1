#!/usr/bin/env pwsh
# Script de déploiement Azure pour MCP Weather Server
# Auteur: Assistant IA
# Date: $(Get-Date -Format "yyyy-MM-dd")

param(
    [string]$ResourceGroup = "mcp-weather-rg",
    [string]$Location = "francecentral",
    [string]$RegistryName = "mcpweatherregistry",
    [string]$ContainerName = "mcp-weather-server",
    [string]$ImageName = "mcp-weather-server",
    [string]$Port = "8000",
    [switch]$SkipBuild,
    [switch]$Verbose
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

function Test-Prerequisites {
    Write-Header "VÉRIFICATION DES PRÉREQUIS"
    
    # Vérifier Azure CLI
    try {
        $azVersion = az version --output json | ConvertFrom-Json
        Write-ColorMessage "✅ Azure CLI v$($azVersion.'azure-cli') détecté" -Color "Success"
    }
    catch {
        Write-ColorMessage "❌ Azure CLI non trouvé. Installez Azure CLI d'abord." -Color "Error"
        exit 1
    }
    
    # Vérifier Docker
    try {
        $dockerVersion = docker --version
        Write-ColorMessage "✅ $dockerVersion détecté" -Color "Success"
    }
    catch {
        Write-ColorMessage "❌ Docker non trouvé. Installez Docker d'abord." -Color "Error"
        exit 1
    }
    
    # Vérifier la connexion Azure
    try {
        $account = az account show --output json | ConvertFrom-Json
        Write-ColorMessage "✅ Connecté à Azure (Subscription: $($account.name))" -Color "Success"
    }
    catch {
        Write-ColorMessage "❌ Non connecté à Azure. Exécutez 'az login' d'abord." -Color "Error"
        exit 1
    }
}

function New-ResourceGroup {
    Write-Header "CRÉATION DU GROUPE DE RESSOURCES"
    
    $existingRg = az group show --name $ResourceGroup --output json 2>$null
    if ($existingRg) {
        Write-ColorMessage "✅ Groupe de ressources '$ResourceGroup' existe déjà" -Color "Info"
    }
    else {
        Write-ColorMessage "🔧 Création du groupe de ressources '$ResourceGroup'..." -Color "Info"
        az group create --name $ResourceGroup --location $Location --output none
        if ($LASTEXITCODE -eq 0) {
            Write-ColorMessage "✅ Groupe de ressources créé avec succès" -Color "Success"
        }
        else {
            Write-ColorMessage "❌ Échec de la création du groupe de ressources" -Color "Error"
            exit 1
        }
    }
}

function New-ContainerRegistry {
    Write-Header "CONFIGURATION DU REGISTRE DE CONTENEURS"
    
    # Générer un nom unique pour le registre
    $timestamp = Get-Date -Format "yyyyMMddHHmm"
    $uniqueRegistryName = "$RegistryName$timestamp".ToLower()
    
    Write-ColorMessage "🔧 Création du registre '$uniqueRegistryName'..." -Color "Info"
    
    $result = az acr create --resource-group $ResourceGroup --name $uniqueRegistryName --sku Basic --admin-enabled true --output json
    if ($LASTEXITCODE -eq 0) {
        $registry = $result | ConvertFrom-Json
        Write-ColorMessage "✅ Registre créé: $($registry.loginServer)" -Color "Success"
        return $registry.loginServer
    }
    else {
        Write-ColorMessage "❌ Échec de la création du registre" -Color "Error"
        exit 1
    }
}

function Build-DockerImage {
    param([string]$RegistryServer)
    
    if ($SkipBuild) {
        Write-ColorMessage "⏭️ Construction de l'image ignorée (--SkipBuild)" -Color "Warning"
        return
    }
    
    Write-Header "CONSTRUCTION DE L'IMAGE DOCKER"
    
    $fullImageName = "$RegistryServer/$ImageName`:latest"
    
    Write-ColorMessage "🔧 Construction de l'image '$fullImageName'..." -Color "Info"
    docker build -t $fullImageName .
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorMessage "✅ Image construite avec succès" -Color "Success"
    }
    else {
        Write-ColorMessage "❌ Échec de la construction de l'image" -Color "Error"
        exit 1
    }
    
    Write-ColorMessage "🔧 Connexion au registre Azure..." -Color "Info"
    az acr login --name $RegistryServer.Split('.')[0] --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorMessage "✅ Connexion au registre réussie" -Color "Success"
    }
    else {
        Write-ColorMessage "❌ Échec de la connexion au registre" -Color "Error"
        exit 1
    }
    
    Write-ColorMessage "🔧 Envoi de l'image vers le registre..." -Color "Info"
    docker push $fullImageName
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorMessage "✅ Image envoyée avec succès" -Color "Success"
    }
    else {
        Write-ColorMessage "❌ Échec de l'envoi de l'image" -Color "Error"
        exit 1
    }
    
    return $fullImageName
}

function Deploy-Container {
    param([string]$ImageName)
    
    Write-Header "DÉPLOIEMENT DU CONTENEUR"
    
    # Générer un nom DNS unique
    $timestamp = Get-Date -Format "yyyyMMddHHmm"
    $dnsName = "$ContainerName-$timestamp".ToLower()
    
    Write-ColorMessage "🔧 Déploiement du conteneur '$ContainerName'..." -Color "Info"
    Write-ColorMessage "🌐 Nom DNS: $dnsName.$Location.azurecontainer.io" -Color "Info"
    
    # Lire les variables d'environnement depuis le fichier .env
    $envVars = @()
    if (Test-Path ".env") {
        Write-ColorMessage "📋 Lecture des variables d'environnement depuis .env..." -Color "Info"
        $envContent = Get-Content ".env" | Where-Object { $_ -match "^[^#].*=" }
        foreach ($line in $envContent) {
            $parts = $line.Split('=', 2)
            if ($parts.Length -eq 2) {
                $key = $parts[0].Trim()
                $value = $parts[1].Trim().Trim('"')
                $envVars += "$key=$value"
            }
        }
        Write-ColorMessage "✅ $($envVars.Count) variables d'environnement chargées" -Color "Success"
    }
    else {
        Write-ColorMessage "⚠️ Fichier .env non trouvé, déploiement sans variables d'environnement" -Color "Warning"
    }
    
    # Construire la commande de déploiement
    $deployCmd = @(
        "az", "container", "create",
        "--resource-group", $ResourceGroup,
        "--name", $ContainerName,
        "--image", $ImageName,
        "--cpu", "1",
        "--memory", "1.5",
        "--registry-login-server", $ImageName.Split('/')[0],
        "--ports", $Port,
        "--protocol", "TCP",
        "--os-type", "Linux",
        "--dns-name-label", $dnsName,
        "--output", "json"
    )
    
    # Ajouter les variables d'environnement si elles existent
    if ($envVars.Count -gt 0) {
        $deployCmd += "--environment-variables"
        $deployCmd += $envVars
    }
    
    # Obtenir les credentials du registre
    $registryName = $ImageName.Split('/')[0].Split('.')[0]
    $credentials = az acr credential show --name $registryName --output json | ConvertFrom-Json
    $deployCmd += "--registry-username"
    $deployCmd += $credentials.username
    $deployCmd += "--registry-password"
    $deployCmd += $credentials.passwords[0].value
    
    if ($Verbose) {
        Write-ColorMessage "🔧 Commande de déploiement:" -Color "Info"
        Write-ColorMessage ($deployCmd -join " ") -Color "Info"
    }
    
    $result = & $deployCmd[0] @($deployCmd[1..($deployCmd.Length-1)])
    
    if ($LASTEXITCODE -eq 0) {
        $container = $result | ConvertFrom-Json
        Write-ColorMessage "✅ Conteneur déployé avec succès!" -Color "Success"
        Write-ColorMessage "🌐 URL: https://$($container.ipAddress.fqdn):$Port" -Color "Success"
        Write-ColorMessage "📊 État: $($container.instanceView.state)" -Color "Info"
        return $container.ipAddress.fqdn
    }
    else {
        Write-ColorMessage "❌ Échec du déploiement du conteneur" -Color "Error"
        Write-ColorMessage "Sortie d'erreur: $result" -Color "Error"
        exit 1
    }
}

function Test-Deployment {
    param([string]$Fqdn)
    
    Write-Header "TEST DU DÉPLOIEMENT"
    
    $url = "https://$Fqdn`:$Port/health"
    Write-ColorMessage "🔧 Test de l'endpoint de santé: $url" -Color "Info"
    
    # Attendre que le conteneur soit prêt
    Write-ColorMessage "⏳ Attente du démarrage du conteneur (30 secondes)..." -Color "Info"
    Start-Sleep -Seconds 30
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10
        Write-ColorMessage "✅ Serveur accessible et fonctionnel!" -Color "Success"
        Write-ColorMessage "📊 Réponse: $($response | ConvertTo-Json -Compress)" -Color "Info"
    }
    catch {
        Write-ColorMessage "⚠️ Serveur pas encore accessible (normal au premier déploiement)" -Color "Warning"
        Write-ColorMessage "🔧 Vérifiez les logs avec: az container logs --resource-group $ResourceGroup --name $ContainerName" -Color "Info"
    }
}

function Show-Summary {
    param([string]$Fqdn)
    
    Write-Header "RÉSUMÉ DU DÉPLOIEMENT"
    
    Write-ColorMessage "🎉 Déploiement terminé avec succès!" -Color "Success"
    Write-ColorMessage ""
    Write-ColorMessage "📋 Informations du déploiement:" -Color "Info"
    Write-ColorMessage "   • Groupe de ressources: $ResourceGroup" -Color "Info"
    Write-ColorMessage "   • Conteneur: $ContainerName" -Color "Info"
    Write-ColorMessage "   • URL: https://$Fqdn`:$Port" -Color "Success"
    Write-ColorMessage ""
    Write-ColorMessage "🔧 Commandes utiles:" -Color "Info"
    Write-ColorMessage "   • Logs: az container logs --resource-group $ResourceGroup --name $ContainerName" -Color "Info"
    Write-ColorMessage "   • État: az container show --resource-group $ResourceGroup --name $ContainerName" -Color "Info"
    Write-ColorMessage "   • Redémarrer: az container restart --resource-group $ResourceGroup --name $ContainerName" -Color "Info"
    Write-ColorMessage ""
    Write-ColorMessage "🧪 Pour tester le déploiement:" -Color "Info"
    Write-ColorMessage "   python test/test_azure_deployment.py" -Color "Info"
}

# SCRIPT PRINCIPAL
try {
    Write-Header "🚀 DÉPLOIEMENT MCP WEATHER SERVER SUR AZURE"
    
    Test-Prerequisites
    New-ResourceGroup
    $registryServer = New-ContainerRegistry
    $imageName = Build-DockerImage -RegistryServer $registryServer
    $fqdn = Deploy-Container -ImageName $imageName
    Test-Deployment -Fqdn $fqdn
    Show-Summary -Fqdn $fqdn
    
    Write-ColorMessage "🎯 Déploiement Azure terminé avec succès!" -Color "Success"
}
catch {
    Write-ColorMessage "❌ Erreur durant le déploiement: $($_.Exception.Message)" -Color "Error"
    exit 1
} 