#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Script de configuration et d'aide pour le déploiement Azure
.DESCRIPTION
    Ce script aide à installer les prérequis et configure l'environnement pour le déploiement Azure
.PARAMETER InstallPrerequisites
    Installe automatiquement les prérequis (Azure CLI, Docker)
.PARAMETER CheckOnly
    Vérifie seulement les prérequis sans rien installer
.EXAMPLE
    .\azure-setup.ps1 -CheckOnly
    .\azure-setup.ps1 -InstallPrerequisites
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$InstallPrerequisites,
    
    [Parameter(Mandatory=$false)]
    [switch]$CheckOnly
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
Write-ColorOutput "🛠️  Configuration Azure pour MCP Weather Server" "Magenta"
Write-ColorOutput "===============================================" "Magenta"

# Vérification du système d'exploitation
$isWindowsOS = $PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows
$isLinuxOS = $PSVersionTable.PSVersion.Major -ge 6 -and $IsLinux
$isMacOSOS = $PSVersionTable.PSVersion.Major -ge 6 -and $IsMacOS

if ($PSVersionTable.PSVersion.Major -lt 6) {
    $isWindowsOS = $true
}

Write-Info "Système détecté: $(if($isWindowsOS){'Windows'}elseif($isLinuxOS){'Linux'}elseif($isMacOSOS){'macOS'}else{'Inconnu'})"

# Fonction pour vérifier Azure CLI
function Test-AzureCLI {
    try {
        $azVersion = az version --output json 2>$null | ConvertFrom-Json
        if ($azVersion) {
            Write-Success "Azure CLI version $($azVersion.'azure-cli') installé"
            return $true
        }
    } catch {
        Write-Error "Azure CLI n'est pas installé ou ne fonctionne pas correctement"
        return $false
    }
    return $false
}

# Fonction pour vérifier Docker
function Test-Docker {
    try {
        $dockerVersion = docker --version 2>$null
        if ($dockerVersion) {
            Write-Success "Docker installé: $dockerVersion"
            return $true
        }
    } catch {
        Write-Error "Docker n'est pas installé ou ne fonctionne pas correctement"
        return $false
    }
    return $false
}

# Fonction pour installer Azure CLI sur Windows
function Install-AzureCLIWindows {
    Write-Step "Installation d'Azure CLI sur Windows..."
    try {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Info "Utilisation de winget pour installer Azure CLI..."
            winget install Microsoft.AzureCLI
        } else {
            Write-Info "Téléchargement et installation d'Azure CLI..."
            $url = "https://aka.ms/installazurecliwindows"
            $output = "$env:TEMP\AzureCLI.msi"
            Invoke-WebRequest -Uri $url -OutFile $output
            Start-Process msiexec.exe -Wait -ArgumentList "/I $output /quiet"
            Remove-Item $output -Force
        }
        Write-Success "Azure CLI installé avec succès"
        return $true
    } catch {
        Write-Error "Erreur lors de l'installation d'Azure CLI: $_"
        return $false
    }
}

# Fonction pour installer Docker sur Windows
function Install-DockerWindows {
    Write-Step "Installation de Docker Desktop sur Windows..."
    Write-Warning "Docker Desktop nécessite une installation manuelle."
    Write-Info "Veuillez télécharger et installer Docker Desktop depuis:"
    Write-ColorOutput "https://www.docker.com/products/docker-desktop/" "Yellow"
    
    $response = Read-Host "Appuyez sur Entrée après avoir installé Docker Desktop"
    return Test-Docker
}

# Vérification des prérequis
Write-Step "Vérification des prérequis..."

$azureCliOk = Test-AzureCLI
$dockerOk = Test-Docker

if ($CheckOnly) {
    Write-ColorOutput "`n📋 Résumé des prérequis:" "Yellow"
    Write-ColorOutput "Azure CLI: $(if($azureCliOk){'✅ Installé'}else{'❌ Non installé'})" "White"
    Write-ColorOutput "Docker: $(if($dockerOk){'✅ Installé'}else{'❌ Non installé'})" "White"
    
    if ($azureCliOk -and $dockerOk) {
        Write-Success "`nTous les prérequis sont installés! Vous pouvez exécuter le déploiement."
    } else {
        Write-Warning "`nCertains prérequis manquent. Exécutez le script avec -InstallPrerequisites pour les installer."
    }
    exit 0
}

# Installation des prérequis si demandé
if ($InstallPrerequisites) {
    Write-Step "Installation des prérequis manquants..."
    
    if (-not $azureCliOk) {
        if ($isWindowsOS) {
            $azureCliOk = Install-AzureCLIWindows
        } else {
            Write-Warning "Installation automatique d'Azure CLI non supportée sur ce système."
            Write-Info "Veuillez installer Azure CLI manuellement:"
            Write-ColorOutput "https://docs.microsoft.com/cli/azure/install-azure-cli" "Yellow"
        }
    }
    
    if (-not $dockerOk) {
        if ($isWindowsOS) {
            $dockerOk = Install-DockerWindows
        } else {
            Write-Warning "Installation automatique de Docker non supportée sur ce système."
            Write-Info "Veuillez installer Docker manuellement:"
            Write-ColorOutput "https://docs.docker.com/get-docker/" "Yellow"
        }
    }
}

# Configuration Azure
if ($azureCliOk) {
    Write-Step "Vérification de la connexion Azure..."
    try {
        $account = az account show --output json 2>$null | ConvertFrom-Json
        if ($account) {
            Write-Success "Connecté à Azure avec: $($account.user.name)"
            Write-ColorOutput "Abonnement: $($account.name)" "Yellow"
        } else {
            Write-Warning "Non connecté à Azure"
            Write-Info "Exécutez 'az login' pour vous connecter"
        }
    } catch {
        Write-Warning "Non connecté à Azure"
        Write-Info "Exécutez 'az login' pour vous connecter"
    }
}

# Génération d'un nom de registre unique
$randomSuffix = Get-Random -Minimum 1000 -Maximum 9999
$suggestedRegistryName = "mcpweather$randomSuffix"

# Affichage des instructions finales
Write-ColorOutput "`n🚀 Prêt pour le déploiement!" "Green"
Write-ColorOutput "=============================" "Green"

if ($azureCliOk -and $dockerOk) {
    Write-ColorOutput "Tous les prérequis sont installés." "Green"
    Write-ColorOutput "`nPour déployer votre serveur MCP Weather:" "White"
    Write-ColorOutput "1. Connectez-vous à Azure (si pas déjà fait):" "White"
    Write-ColorOutput "   az login" "Gray"
    Write-ColorOutput "`n2. Exécutez le script de déploiement:" "White"
    Write-ColorOutput "   .\deploy-azure.ps1 -ContainerRegistryName '$suggestedRegistryName'" "Gray"
    Write-ColorOutput "`n3. Ou avec des paramètres personnalisés:" "White"
    Write-ColorOutput "   .\deploy-azure.ps1 -ContainerRegistryName 'votre-nom-unique' -ResourceGroupName 'mon-rg' -Location 'France Central'" "Gray"
} else {
    Write-Warning "Certains prérequis manquent encore."
    Write-Info "Installez les composants manquants puis relancez ce script avec -CheckOnly"
}

Write-ColorOutput "`n📚 Ressources utiles:" "Blue"
Write-ColorOutput "• Documentation Azure CLI: https://docs.microsoft.com/cli/azure/" "Gray"
Write-ColorOutput "• Documentation Docker: https://docs.docker.com/" "Gray"
Write-ColorOutput "• Azure Container Instances: https://docs.microsoft.com/azure/container-instances/" "Gray"

Write-ColorOutput "`n💡 Conseils:" "Yellow"
Write-ColorOutput "• Le nom du registre de conteneurs doit être unique globalement" "Gray"
Write-ColorOutput "• Choisissez une région Azure proche de vos utilisateurs" "Gray"
Write-ColorOutput "• Les logs du conteneur sont accessibles via Azure CLI ou le portail Azure" "Gray" 