#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Script de gestion pour le serveur MCP Weather déployé sur Azure
.DESCRIPTION
    Ce script permet de gérer le serveur MCP Weather déployé sur Azure Container Instances
.PARAMETER Action
    Action à effectuer: status, logs, restart, stop, start, delete, update
.PARAMETER ResourceGroupName
    Nom du groupe de ressources Azure
.PARAMETER ContainerInstanceName
    Nom de l'instance de conteneur
.PARAMETER Follow
    Suit les logs en temps réel (pour l'action logs)
.EXAMPLE
    .\azure-manage.ps1 -Action status
    .\azure-manage.ps1 -Action logs -Follow
    .\azure-manage.ps1 -Action restart -ResourceGroupName "mon-rg"
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("status", "logs", "restart", "stop", "start", "delete", "update", "help")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "mcp-weather-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerInstanceName = "mcp-weather-server",
    
    [Parameter(Mandatory=$false)]
    [switch]$Follow
)

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

function Test-AzureConnection {
    try {
        $account = az account show --output json 2>$null | ConvertFrom-Json
        if ($account) {
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

function Test-ContainerExists {
    try {
        az container show --resource-group $ResourceGroupName --name $ContainerInstanceName --output none 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Show-Help {
    Write-ColorOutput "🛠️  Gestionnaire Azure MCP Weather Server" "Magenta"
    Write-ColorOutput "=========================================" "Magenta"
    Write-ColorOutput ""
    Write-ColorOutput "Actions disponibles:" "Yellow"
    Write-ColorOutput "  status   - Affiche l'état du conteneur" "White"
    Write-ColorOutput "  logs     - Affiche les logs du conteneur" "White"
    Write-ColorOutput "  restart  - Redémarre le conteneur" "White"
    Write-ColorOutput "  stop     - Arrête le conteneur" "White"
    Write-ColorOutput "  start    - Démarre le conteneur" "White"
    Write-ColorOutput "  update   - Met à jour le conteneur avec une nouvelle image" "White"
    Write-ColorOutput "  delete   - Supprime complètement le déploiement" "White"
    Write-ColorOutput "  help     - Affiche cette aide" "White"
    Write-ColorOutput ""
    Write-ColorOutput "Exemples d'utilisation:" "Yellow"
    Write-ColorOutput "  .\azure-manage.ps1 -Action status" "Gray"
    Write-ColorOutput "  .\azure-manage.ps1 -Action logs -Follow" "Gray"
    Write-ColorOutput "  .\azure-manage.ps1 -Action restart" "Gray"
    Write-ColorOutput "  .\azure-manage.ps1 -Action delete -ResourceGroupName 'mon-rg'" "Gray"
}

function Get-ContainerStatus {
    Write-Step "Récupération de l'état du conteneur..."
    
    try {
        $containerInfo = az container show --resource-group $ResourceGroupName --name $ContainerInstanceName --output json | ConvertFrom-Json
        
        Write-Success "Informations du conteneur récupérées"
        Write-ColorOutput ""
        Write-ColorOutput "📊 État du conteneur:" "Green"
        Write-ColorOutput "=====================" "Green"
        Write-ColorOutput "  • Nom: $($containerInfo.name)" "White"
        Write-ColorOutput "  • État: $($containerInfo.instanceView.currentState.state)" "White"
        Write-ColorOutput "  • Heure de démarrage: $($containerInfo.instanceView.currentState.startTime)" "White"
        Write-ColorOutput "  • CPU: $($containerInfo.containers[0].resources.requests.cpu) cœurs" "White"
        Write-ColorOutput "  • Mémoire: $($containerInfo.containers[0].resources.requests.memoryInGB) GB" "White"
        Write-ColorOutput "  • Adresse IP: $($containerInfo.ipAddress.ip)" "White"
        
        if ($containerInfo.ipAddress.fqdn) {
            Write-ColorOutput "  • FQDN: $($containerInfo.ipAddress.fqdn)" "White"
            Write-ColorOutput "  • URL: http://$($containerInfo.ipAddress.fqdn):8000" "White"
        }
        
        Write-ColorOutput "  • Politique de redémarrage: $($containerInfo.restartPolicy)" "White"
        Write-ColorOutput "  • Groupe de ressources: $($containerInfo.resourceGroup)" "White"
        Write-ColorOutput "  • Région: $($containerInfo.location)" "White"
        
        # Afficher les événements récents
        if ($containerInfo.instanceView.events) {
            Write-ColorOutput ""
            Write-ColorOutput "📋 Événements récents:" "Yellow"
            $containerInfo.instanceView.events | ForEach-Object {
                Write-ColorOutput "  • $($_.firstTimestamp): $($_.message)" "Gray"
            }
        }
        
    } catch {
        Write-Error "Erreur lors de la récupération de l'état: $_"
        return $false
    }
    return $true
}

function Get-ContainerLogs {
    Write-Step "Récupération des logs du conteneur..."
    
    try {
        if ($Follow) {
            Write-Info "Suivi des logs en temps réel (Ctrl+C pour arrêter)..."
            az container logs --resource-group $ResourceGroupName --name $ContainerInstanceName --follow
        } else {
            $logs = az container logs --resource-group $ResourceGroupName --name $ContainerInstanceName
            Write-Success "Logs récupérés"
            Write-ColorOutput ""
            Write-ColorOutput "📜 Logs du conteneur:" "Green"
            Write-ColorOutput "====================" "Green"
            Write-ColorOutput $logs "White"
        }
    } catch {
        Write-Error "Erreur lors de la récupération des logs: $_"
        return $false
    }
    return $true
}

function Restart-Container {
    Write-Step "Redémarrage du conteneur..."
    
    try {
        az container restart --resource-group $ResourceGroupName --name $ContainerInstanceName --output none
        Write-Success "Conteneur redémarré avec succès"
        
        # Attendre un peu et afficher le nouvel état
        Start-Sleep -Seconds 5
        Get-ContainerStatus
    } catch {
        Write-Error "Erreur lors du redémarrage: $_"
        return $false
    }
    return $true
}

function Stop-Container {
    Write-Step "Arrêt du conteneur..."
    
    try {
        az container stop --resource-group $ResourceGroupName --name $ContainerInstanceName --output none
        Write-Success "Conteneur arrêté avec succès"
    } catch {
        Write-Error "Erreur lors de l'arrêt: $_"
        return $false
    }
    return $true
}

function Start-Container {
    Write-Step "Démarrage du conteneur..."
    
    try {
        az container start --resource-group $ResourceGroupName --name $ContainerInstanceName --output none
        Write-Success "Conteneur démarré avec succès"
        
        # Attendre un peu et afficher l'état
        Start-Sleep -Seconds 5
        Get-ContainerStatus
    } catch {
        Write-Error "Erreur lors du démarrage: $_"
        return $false
    }
    return $true
}

function Update-Container {
    Write-Warning "La mise à jour nécessite de reconstruire et redéployer l'image."
    Write-Info "Cette opération va:"
    Write-ColorOutput "  1. Reconstruire l'image Docker localement" "Gray"
    Write-ColorOutput "  2. La pousser vers Azure Container Registry" "Gray"
    Write-ColorOutput "  3. Redémarrer le conteneur avec la nouvelle image" "Gray"
    
    $confirmation = Read-Host "Voulez-vous continuer? (o/N)"
    if ($confirmation -ne "o" -and $confirmation -ne "O" -and $confirmation -ne "oui") {
        Write-Warning "Mise à jour annulée"
        return $false
    }
    
    Write-Info "Pour effectuer la mise à jour, veuillez exécuter le script de déploiement:"
    Write-ColorOutput ".\deploy-azure.ps1 -ContainerRegistryName 'votre-registre' -ResourceGroupName '$ResourceGroupName' -ContainerInstanceName '$ContainerInstanceName'" "Yellow"
    
    return $true
}

function Remove-Deployment {
    Write-Warning "⚠️  ATTENTION: Cette action va supprimer COMPLÈTEMENT le déploiement!"
    Write-ColorOutput "Cela inclut:" "Red"
    Write-ColorOutput "  • L'instance de conteneur" "Red"
    Write-ColorOutput "  • Le groupe de ressources (si vide)" "Red"
    Write-ColorOutput "  • Toutes les données associées" "Red"
    
    $confirmation = Read-Host "Êtes-vous sûr de vouloir supprimer le déploiement? Tapez 'SUPPRIMER' pour confirmer"
    if ($confirmation -ne "SUPPRIMER") {
        Write-Warning "Suppression annulée"
        return $false
    }
    
    Write-Step "Suppression de l'instance de conteneur..."
    try {
        az container delete --resource-group $ResourceGroupName --name $ContainerInstanceName --yes --output none
        Write-Success "Instance de conteneur supprimée"
        
        # Demander si on veut supprimer le groupe de ressources
        $deleteRG = Read-Host "Voulez-vous aussi supprimer le groupe de ressources '$ResourceGroupName'? (o/N)"
        if ($deleteRG -eq "o" -or $deleteRG -eq "O" -or $deleteRG -eq "oui") {
            Write-Step "Suppression du groupe de ressources..."
            az group delete --name $ResourceGroupName --yes --no-wait
            Write-Success "Suppression du groupe de ressources initiée (en arrière-plan)"
        }
        
    } catch {
        Write-Error "Erreur lors de la suppression: $_"
        return $false
    }
    return $true
}

# Script principal
Write-ColorOutput "🌤️  Gestionnaire MCP Weather Server - Azure" "Magenta"
Write-ColorOutput "============================================" "Magenta"

# Vérifier la connexion Azure
if (-not (Test-AzureConnection)) {
    Write-Error "Vous n'êtes pas connecté à Azure. Exécutez 'az login' pour vous connecter."
    exit 1
}

# Afficher l'aide si demandé
if ($Action -eq "help") {
    Show-Help
    exit 0
}

# Vérifier que le conteneur existe (sauf pour l'aide)
if (-not (Test-ContainerExists)) {
    Write-Error "Le conteneur '$ContainerInstanceName' n'existe pas dans le groupe de ressources '$ResourceGroupName'"
    Write-Info "Vérifiez les noms ou déployez d'abord le conteneur avec deploy-azure.ps1"
    exit 1
}

# Exécuter l'action demandée
switch ($Action) {
    "status" {
        Get-ContainerStatus
    }
    "logs" {
        Get-ContainerLogs
    }
    "restart" {
        Restart-Container
    }
    "stop" {
        Stop-Container
    }
    "start" {
        Start-Container
    }
    "update" {
        Update-Container
    }
    "delete" {
        Remove-Deployment
    }
    default {
        Write-Error "Action non reconnue: $Action"
        Show-Help
        exit 1
    }
}

Write-ColorOutput ""
Write-Success "Opération terminée!" 