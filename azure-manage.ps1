#!/usr/bin/env pwsh
# Script de gestion Azure pour MCP Weather Server
# Auteur: Assistant IA
# Date: $(Get-Date -Format "yyyy-MM-dd")

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("status", "logs", "restart", "stop", "start", "delete", "url")]
    [string]$Action,
    
    [string]$ResourceGroup = "mcp-weather-rg",
    [string]$ContainerName = "mcp-weather-server",
    [int]$LogLines = 50,
    [switch]$Follow
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

function Test-ContainerExists {
    try {
        $container = az container show --resource-group $ResourceGroup --name $ContainerName --output json 2>$null
        if ($container) {
            return $container | ConvertFrom-Json
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-ContainerStatus {
    Write-Header "📊 ÉTAT DU CONTENEUR"
    
    $container = Test-ContainerExists
    if (-not $container) {
        Write-ColorMessage "❌ Conteneur '$ContainerName' non trouvé dans '$ResourceGroup'" -Color "Error"
        return
    }
    
    Write-ColorMessage "📋 Informations du conteneur:" -Color "Info"
    Write-ColorMessage "   • Nom: $($container.name)" -Color "Info"
    Write-ColorMessage "   • État: $($container.instanceView.state)" -Color $(if ($container.instanceView.state -eq "Running") { "Success" } else { "Warning" })
    Write-ColorMessage "   • Groupe de ressources: $($container.resourceGroup)" -Color "Info"
    Write-ColorMessage "   • Localisation: $($container.location)" -Color "Info"
    
    if ($container.ipAddress) {
        Write-ColorMessage "   • IP publique: $($container.ipAddress.ip)" -Color "Info"
        if ($container.ipAddress.fqdn) {
            Write-ColorMessage "   • FQDN: $($container.ipAddress.fqdn)" -Color "Success"
            Write-ColorMessage "   • URL: https://$($container.ipAddress.fqdn):8000" -Color "Success"
        }
        Write-ColorMessage "   • Ports: $($container.ipAddress.ports | ForEach-Object { "$($_.port)/$($_.protocol)" } | Join-String -Separator ', ')" -Color "Info"
    }
    
    Write-ColorMessage "   • CPU: $($container.containers[0].resources.requests.cpu)" -Color "Info"
    Write-ColorMessage "   • Mémoire: $($container.containers[0].resources.requests.memoryInGB) GB" -Color "Info"
    Write-ColorMessage "   • Image: $($container.containers[0].image)" -Color "Info"
    
    if ($container.instanceView.currentState) {
        Write-ColorMessage "   • Démarré: $($container.instanceView.currentState.startTime)" -Color "Info"
        if ($container.instanceView.currentState.exitCode) {
            Write-ColorMessage "   • Code de sortie: $($container.instanceView.currentState.exitCode)" -Color "Warning"
        }
    }
    
    # Test de connectivité si le conteneur est en cours d'exécution
    if ($container.instanceView.state -eq "Running" -and $container.ipAddress.fqdn) {
        Write-ColorMessage ""
        Write-ColorMessage "🔧 Test de connectivité..." -Color "Info"
        $url = "https://$($container.ipAddress.fqdn):8000/health"
        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 5
            Write-ColorMessage "✅ Serveur accessible et répond" -Color "Success"
        }
        catch {
            Write-ColorMessage "⚠️ Serveur non accessible: $($_.Exception.Message)" -Color "Warning"
        }
    }
}

function Get-ContainerLogs {
    Write-Header "📜 LOGS DU CONTENEUR"
    
    $container = Test-ContainerExists
    if (-not $container) {
        Write-ColorMessage "❌ Conteneur '$ContainerName' non trouvé dans '$ResourceGroup'" -Color "Error"
        return
    }
    
    Write-ColorMessage "📋 Récupération des $LogLines dernières lignes de logs..." -Color "Info"
    
    if ($Follow) {
        Write-ColorMessage "👀 Mode suivi activé (Ctrl+C pour arrêter)" -Color "Info"
        az container logs --resource-group $ResourceGroup --name $ContainerName --follow
    }
    else {
        az container logs --resource-group $ResourceGroup --name $ContainerName --tail $LogLines
    }
}

function Restart-Container {
    Write-Header "🔄 REDÉMARRAGE DU CONTENEUR"
    
    $container = Test-ContainerExists
    if (-not $container) {
        Write-ColorMessage "❌ Conteneur '$ContainerName' non trouvé dans '$ResourceGroup'" -Color "Error"
        return
    }
    
    Write-ColorMessage "🔧 Redémarrage du conteneur '$ContainerName'..." -Color "Info"
    az container restart --resource-group $ResourceGroup --name $ContainerName --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorMessage "✅ Conteneur redémarré avec succès" -Color "Success"
        Write-ColorMessage "⏳ Attente du démarrage (15 secondes)..." -Color "Info"
        Start-Sleep -Seconds 15
        Get-ContainerStatus
    }
    else {
        Write-ColorMessage "❌ Échec du redémarrage du conteneur" -Color "Error"
    }
}

function Stop-Container {
    Write-Header "⏹️ ARRÊT DU CONTENEUR"
    
    $container = Test-ContainerExists
    if (-not $container) {
        Write-ColorMessage "❌ Conteneur '$ContainerName' non trouvé dans '$ResourceGroup'" -Color "Error"
        return
    }
    
    if ($container.instanceView.state -ne "Running") {
        Write-ColorMessage "⚠️ Le conteneur n'est pas en cours d'exécution (État: $($container.instanceView.state))" -Color "Warning"
        return
    }
    
    Write-ColorMessage "🔧 Arrêt du conteneur '$ContainerName'..." -Color "Info"
    az container stop --resource-group $ResourceGroup --name $ContainerName --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorMessage "✅ Conteneur arrêté avec succès" -Color "Success"
    }
    else {
        Write-ColorMessage "❌ Échec de l'arrêt du conteneur" -Color "Error"
    }
}

function Start-Container {
    Write-Header "▶️ DÉMARRAGE DU CONTENEUR"
    
    $container = Test-ContainerExists
    if (-not $container) {
        Write-ColorMessage "❌ Conteneur '$ContainerName' non trouvé dans '$ResourceGroup'" -Color "Error"
        return
    }
    
    if ($container.instanceView.state -eq "Running") {
        Write-ColorMessage "⚠️ Le conteneur est déjà en cours d'exécution" -Color "Warning"
        return
    }
    
    Write-ColorMessage "🔧 Démarrage du conteneur '$ContainerName'..." -Color "Info"
    az container start --resource-group $ResourceGroup --name $ContainerName --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorMessage "✅ Conteneur démarré avec succès" -Color "Success"
        Write-ColorMessage "⏳ Attente du démarrage (15 secondes)..." -Color "Info"
        Start-Sleep -Seconds 15
        Get-ContainerStatus
    }
    else {
        Write-ColorMessage "❌ Échec du démarrage du conteneur" -Color "Error"
    }
}

function Remove-Container {
    Write-Header "🗑️ SUPPRESSION DU CONTENEUR"
    
    $container = Test-ContainerExists
    if (-not $container) {
        Write-ColorMessage "❌ Conteneur '$ContainerName' non trouvé dans '$ResourceGroup'" -Color "Error"
        return
    }
    
    Write-ColorMessage "⚠️ ATTENTION: Cette action va supprimer définitivement le conteneur!" -Color "Warning"
    $confirmation = Read-Host "Tapez 'OUI' pour confirmer la suppression"
    
    if ($confirmation -ne "OUI") {
        Write-ColorMessage "❌ Suppression annulée" -Color "Info"
        return
    }
    
    Write-ColorMessage "🔧 Suppression du conteneur '$ContainerName'..." -Color "Info"
    az container delete --resource-group $ResourceGroup --name $ContainerName --yes --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorMessage "✅ Conteneur supprimé avec succès" -Color "Success"
    }
    else {
        Write-ColorMessage "❌ Échec de la suppression du conteneur" -Color "Error"
    }
}

function Get-ContainerUrl {
    $container = Test-ContainerExists
    if (-not $container) {
        Write-ColorMessage "❌ Conteneur '$ContainerName' non trouvé dans '$ResourceGroup'" -Color "Error"
        return
    }
    
    if ($container.ipAddress.fqdn) {
        $url = "https://$($container.ipAddress.fqdn):8000"
        Write-ColorMessage "🌐 URL du serveur: $url" -Color "Success"
        
        # Copier dans le presse-papiers si possible
        try {
            $url | Set-Clipboard
            Write-ColorMessage "📋 URL copiée dans le presse-papiers" -Color "Info"
        }
        catch {
            # Ignore si le presse-papiers n'est pas disponible
        }
    }
    else {
        Write-ColorMessage "❌ Aucune URL publique disponible pour ce conteneur" -Color "Error"
    }
}

# SCRIPT PRINCIPAL
try {
    Write-Header "🛠️ GESTION MCP WEATHER SERVER AZURE"
    
    # Vérifier la connexion Azure
    try {
        $account = az account show --output json 2>$null | ConvertFrom-Json
        Write-ColorMessage "✅ Connecté à Azure (Subscription: $($account.name))" -Color "Success"
    }
    catch {
        Write-ColorMessage "❌ Non connecté à Azure. Exécutez 'az login' d'abord." -Color "Error"
        exit 1
    }
    
    switch ($Action.ToLower()) {
        "status" { Get-ContainerStatus }
        "logs" { Get-ContainerLogs }
        "restart" { Restart-Container }
        "stop" { Stop-Container }
        "start" { Start-Container }
        "delete" { Remove-Container }
        "url" { Get-ContainerUrl }
        default {
            Write-ColorMessage "❌ Action non reconnue: $Action" -Color "Error"
            Write-ColorMessage "Actions disponibles: status, logs, restart, stop, start, delete, url" -Color "Info"
            exit 1
        }
    }
}
catch {
    Write-ColorMessage "❌ Erreur durant l'exécution: $($_.Exception.Message)" -Color "Error"
    exit 1
} 