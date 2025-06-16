#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Script de nettoyage pour les ressources Azure MCP Weather
.DESCRIPTION
    Ce script supprime les ressources Azure créées lors d'un déploiement échoué
.PARAMETER ResourceGroupName
    Nom du groupe de ressources à nettoyer
.PARAMETER ContainerRegistryName
    Nom du registre de conteneurs à supprimer
.PARAMETER Force
    Force la suppression sans demander de confirmation
.EXAMPLE
    .\azure-cleanup.ps1 -ResourceGroupName "mcp-weather-rg"
    .\azure-cleanup.ps1 -ResourceGroupName "mcp-weather-rg" -Force
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "mcp-weather-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerRegistryName,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
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

# En-tête
Write-ColorOutput "🧹 Nettoyage des ressources Azure MCP Weather" "Magenta"
Write-ColorOutput "=============================================" "Magenta"

# Vérifier la connexion Azure
Write-Step "Vérification de la connexion Azure..."
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    if ($account) {
        Write-Success "Connecté à Azure avec: $($account.user.name)"
        Write-ColorOutput "Abonnement: $($account.name)" "Yellow"
    } else {
        Write-Error "Vous n'êtes pas connecté à Azure. Exécutez 'az login' pour vous connecter."
        exit 1
    }
} catch {
    Write-Error "Vous n'êtes pas connecté à Azure. Exécutez 'az login' pour vous connecter."
    exit 1
}

# Vérifier si le groupe de ressources existe
Write-Step "Vérification du groupe de ressources '$ResourceGroupName'..."
$rgExists = az group exists --name $ResourceGroupName --output tsv

if ($rgExists -eq "false") {
    Write-Warning "Le groupe de ressources '$ResourceGroupName' n'existe pas."
    Write-Info "Rien à nettoyer."
    exit 0
}

Write-Success "Groupe de ressources '$ResourceGroupName' trouvé"

# Lister les ressources dans le groupe
Write-Step "Analyse des ressources dans le groupe '$ResourceGroupName'..."
try {
    $resources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    
    if ($resources.Count -eq 0) {
        Write-Warning "Aucune ressource trouvée dans le groupe '$ResourceGroupName'"
    } else {
        Write-ColorOutput "`n📋 Ressources trouvées:" "Yellow"
        foreach ($resource in $resources) {
            Write-ColorOutput "  • $($resource.name) ($($resource.type))" "White"
        }
    }
} catch {
    Write-Warning "Impossible de lister les ressources: $_"
}

# Demander confirmation si pas en mode Force
if (-not $Force) {
    Write-ColorOutput "`n⚠️  ATTENTION: Cette action va supprimer TOUTES les ressources!" "Red"
    Write-ColorOutput "Cela inclut:" "Red"
    Write-ColorOutput "  • Toutes les instances de conteneurs" "Red"
    Write-ColorOutput "  • Le registre de conteneurs (et toutes ses images)" "Red"
    Write-ColorOutput "  • Le groupe de ressources complet" "Red"
    Write-ColorOutput "  • Toutes les données associées" "Red"
    
    $confirmation = Read-Host "`nÊtes-vous sûr de vouloir supprimer le groupe de ressources '$ResourceGroupName'? Tapez 'SUPPRIMER' pour confirmer"
    if ($confirmation -ne "SUPPRIMER") {
        Write-Warning "Nettoyage annulé par l'utilisateur."
        exit 0
    }
}

# Supprimer le groupe de ressources
Write-Step "Suppression du groupe de ressources '$ResourceGroupName'..."
try {
    Write-Info "Cette opération peut prendre plusieurs minutes..."
    az group delete --name $ResourceGroupName --yes --no-wait
    Write-Success "Suppression du groupe de ressources initiée (en arrière-plan)"
    
    # Attendre un peu et vérifier le statut
    Write-Info "Vérification du statut de suppression..."
    Start-Sleep -Seconds 5
    
    $deleteStatus = az group exists --name $ResourceGroupName --output tsv
    if ($deleteStatus -eq "false") {
        Write-Success "Groupe de ressources supprimé avec succès"
    } else {
        Write-Info "Suppression en cours... Vous pouvez vérifier le statut avec:"
        Write-ColorOutput "  az group show --name $ResourceGroupName --query 'properties.provisioningState'" "Gray"
    }
    
} catch {
    Write-Error "Erreur lors de la suppression: $_"
    exit 1
}

# Nettoyage local des images Docker (optionnel)
Write-Step "Nettoyage des images Docker locales..."
try {
    if ($ContainerRegistryName) {
        $imageName = "$ContainerRegistryName.azurecr.io/mcp-weather-server"
        
        # Supprimer les images locales
        $localImages = docker images --filter "reference=$imageName*" --format "{{.Repository}}:{{.Tag}}" 2>$null
        if ($localImages) {
            Write-Info "Suppression des images Docker locales..."
            foreach ($image in $localImages) {
                docker rmi $image --force 2>$null
                Write-ColorOutput "  • Image supprimée: $image" "Gray"
            }
        }
    }
    
    # Nettoyage général Docker
    Write-Info "Nettoyage général Docker..."
    docker system prune -f 2>$null
    Write-Success "Images Docker locales nettoyées"
    
} catch {
    Write-Warning "Erreur lors du nettoyage Docker: $_"
}

# Résumé final
Write-ColorOutput "`n🎉 Nettoyage terminé!" "Green"
Write-ColorOutput "=====================" "Green"
Write-ColorOutput "✅ Groupe de ressources '$ResourceGroupName' supprimé" "Green"
Write-ColorOutput "✅ Images Docker locales nettoyées" "Green"

Write-ColorOutput "`n💡 Prochaines étapes:" "Yellow"
Write-ColorOutput "• Vous pouvez maintenant relancer le déploiement avec:" "White"
Write-ColorOutput "  .\deploy-azure.ps1 -ContainerRegistryName 'nouveau-nom-unique'" "Gray"
Write-ColorOutput "• Ou vérifier les prérequis avec:" "White"
Write-ColorOutput "  .\azure-setup.ps1 -CheckOnly" "Gray"

Write-ColorOutput "`n📊 Vérification du statut:" "Blue"
Write-ColorOutput "• Vérifier que le groupe est supprimé:" "White"
Write-ColorOutput "  az group exists --name $ResourceGroupName" "Gray"
Write-ColorOutput "• Lister tous vos groupes de ressources:" "White"
Write-ColorOutput "  az group list --output table" "Gray" 