#!/bin/bash

# Script de configuration et d'aide pour le déploiement Azure
# Version Linux du script azure-setup.ps1

set -e

# Variables par défaut
INSTALL_PREREQUISITES=false
CHECK_ONLY=false

# Fonction d'aide
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --install-prerequisites    Installe automatiquement les prérequis (Azure CLI, Docker)"
    echo "  --check-only              Vérifie seulement les prérequis sans rien installer"
    echo "  -h, --help                Affiche cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 --check-only"
    echo "  $0 --install-prerequisites"
}

# Traitement des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-prerequisites)
            INSTALL_PREREQUISITES=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

# Fonctions de couleur
write_color() {
    local message="$1"
    local color="$2"
    case $color in
        "red") echo -e "\033[31m$message\033[0m" ;;
        "green") echo -e "\033[32m$message\033[0m" ;;
        "yellow") echo -e "\033[33m$message\033[0m" ;;
        "blue") echo -e "\033[34m$message\033[0m" ;;
        "magenta") echo -e "\033[35m$message\033[0m" ;;
        "cyan") echo -e "\033[36m$message\033[0m" ;;
        "gray") echo -e "\033[37m$message\033[0m" ;;
        *) echo "$message" ;;
    esac
}

write_step() {
    write_color "🔄 $1" "cyan"
}

write_success() {
    write_color "✅ $1" "green"
}

write_error() {
    write_color "❌ $1" "red"
}

write_warning() {
    write_color "⚠️  $1" "yellow"
}

write_info() {
    write_color "ℹ️  $1" "blue"
}

# En-tête
write_color "🛠️  Configuration Azure pour MCP Weather Server" "magenta"
write_color "===============================================" "magenta"

# Détection du système d'exploitation
OS_TYPE=$(uname -s)
DISTRO=""

if [[ "$OS_TYPE" == "Linux" ]]; then
    if command -v lsb_release &> /dev/null; then
        DISTRO=$(lsb_release -si)
    elif [[ -f /etc/os-release ]]; then
        DISTRO=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    fi
    write_info "Système détecté: Linux ($DISTRO)"
elif [[ "$OS_TYPE" == "Darwin" ]]; then
    write_info "Système détecté: macOS"
else
    write_info "Système détecté: $OS_TYPE"
fi

# Fonction pour vérifier Azure CLI
test_azure_cli() {
    if command -v az &> /dev/null; then
        local az_version=$(az version --output json 2>/dev/null | jq -r '."azure-cli"' 2>/dev/null || echo "unknown")
        if [[ "$az_version" != "null" && "$az_version" != "unknown" ]]; then
            write_success "Azure CLI version $az_version installé"
            return 0
        fi
    fi
    write_error "Azure CLI n'est pas installé ou ne fonctionne pas correctement"
    return 1
}

# Fonction pour vérifier Docker
test_docker() {
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            write_success "Docker installé: $docker_version"
            return 0
        fi
    fi
    write_error "Docker n'est pas installé ou ne fonctionne pas correctement"
    return 1
}

# Fonction pour installer Azure CLI sur Linux
install_azure_cli_linux() {
    write_step "Installation d'Azure CLI sur Linux..."
    
    case "$DISTRO" in
        "ubuntu"|"debian")
            write_info "Installation via apt pour Ubuntu/Debian..."
            curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
            ;;
        "centos"|"rhel"|"fedora")
            write_info "Installation via yum/dnf pour CentOS/RHEL/Fedora..."
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            if command -v dnf &> /dev/null; then
                sudo dnf install -y azure-cli
            else
                sudo yum install -y azure-cli
            fi
            ;;
        *)
            write_warning "Distribution non reconnue. Installation via pip..."
            if command -v pip3 &> /dev/null; then
                pip3 install --user azure-cli
            elif command -v pip &> /dev/null; then
                pip install --user azure-cli
            else
                write_error "pip non trouvé. Veuillez installer Azure CLI manuellement."
                return 1
            fi
            ;;
    esac
    
    if test_azure_cli; then
        write_success "Azure CLI installé avec succès"
        return 0
    else
        write_error "Erreur lors de l'installation d'Azure CLI"
        return 1
    fi
}

# Fonction pour installer Docker sur Linux
install_docker_linux() {
    write_step "Installation de Docker sur Linux..."
    
    case "$DISTRO" in
        "ubuntu"|"debian")
            write_info "Installation de Docker via apt pour Ubuntu/Debian..."
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        "centos"|"rhel"|"fedora")
            write_info "Installation de Docker via yum/dnf pour CentOS/RHEL/Fedora..."
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            if command -v dnf &> /dev/null; then
                sudo dnf install -y docker-ce docker-ce-cli containerd.io
            else
                sudo yum install -y docker-ce docker-ce-cli containerd.io
            fi
            ;;
        *)
            write_warning "Distribution non reconnue. Veuillez installer Docker manuellement."
            write_info "Consultez: https://docs.docker.com/engine/install/"
            return 1
            ;;
    esac
    
    # Démarrer et activer Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Ajouter l'utilisateur au groupe docker
    sudo usermod -aG docker $USER
    write_warning "Vous devez vous déconnecter et vous reconnecter pour utiliser Docker sans sudo"
    
    if test_docker; then
        write_success "Docker installé avec succès"
        return 0
    else
        write_error "Erreur lors de l'installation de Docker"
        return 1
    fi
}

# Vérification des prérequis
write_step "Vérification des prérequis..."

azure_cli_ok=false
docker_ok=false

if test_azure_cli; then
    azure_cli_ok=true
fi

if test_docker; then
    docker_ok=true
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
    echo ""
    write_color "📋 Résumé des prérequis:" "yellow"
    if [[ "$azure_cli_ok" == "true" ]]; then
        write_color "Azure CLI: ✅ Installé" "white"
    else
        write_color "Azure CLI: ❌ Non installé" "white"
    fi
    
    if [[ "$docker_ok" == "true" ]]; then
        write_color "Docker: ✅ Installé" "white"
    else
        write_color "Docker: ❌ Non installé" "white"
    fi
    
    if [[ "$azure_cli_ok" == "true" && "$docker_ok" == "true" ]]; then
        echo ""
        write_success "Tous les prérequis sont installés! Vous pouvez exécuter le déploiement."
    else
        echo ""
        write_warning "Certains prérequis manquent. Exécutez le script avec --install-prerequisites pour les installer."
    fi
    exit 0
fi

# Installation des prérequis si demandé
if [[ "$INSTALL_PREREQUISITES" == "true" ]]; then
    write_step "Installation des prérequis manquants..."
    
    if [[ "$azure_cli_ok" != "true" ]]; then
        if [[ "$OS_TYPE" == "Linux" ]]; then
            if install_azure_cli_linux; then
                azure_cli_ok=true
            fi
        else
            write_warning "Installation automatique d'Azure CLI non supportée sur ce système."
            write_info "Veuillez installer Azure CLI manuellement:"
            write_color "https://docs.microsoft.com/cli/azure/install-azure-cli" "yellow"
        fi
    fi
    
    if [[ "$docker_ok" != "true" ]]; then
        if [[ "$OS_TYPE" == "Linux" ]]; then
            if install_docker_linux; then
                docker_ok=true
            fi
        else
            write_warning "Installation automatique de Docker non supportée sur ce système."
            write_info "Veuillez installer Docker manuellement:"
            write_color "https://docs.docker.com/get-docker/" "yellow"
        fi
    fi
fi

# Configuration Azure
if [[ "$azure_cli_ok" == "true" ]]; then
    write_step "Vérification de la connexion Azure..."
    if account_info=$(az account show --output json 2>/dev/null); then
        user_name=$(echo "$account_info" | jq -r '.user.name')
        subscription_name=$(echo "$account_info" | jq -r '.name')
        write_success "Connecté à Azure avec: $user_name"
        write_color "Abonnement: $subscription_name" "yellow"
    else
        write_warning "Non connecté à Azure"
        write_info "Exécutez 'az login' pour vous connecter"
    fi
fi

# Génération d'un nom de registre unique
random_suffix=$((RANDOM % 9000 + 1000))
suggested_registry_name="mcpweather$random_suffix"

# Affichage des instructions finales
echo ""
write_color "🚀 Prêt pour le déploiement!" "green"
write_color "=============================" "green"

if [[ "$azure_cli_ok" == "true" && "$docker_ok" == "true" ]]; then
    write_color "Tous les prérequis sont installés." "green"
    echo ""
    write_color "Pour déployer votre serveur MCP Weather:" "white"
    write_color "1. Connectez-vous à Azure (si pas déjà fait):" "white"
    write_color "   az login" "gray"
    echo ""
    write_color "2. Exécutez le script de déploiement:" "white"
    write_color "   ./deploy-azure.sh --container-registry-name '$suggested_registry_name'" "gray"
    echo ""
    write_color "3. Ou avec des paramètres personnalisés:" "white"
    write_color "   ./deploy-azure.sh --container-registry-name 'votre-nom-unique' --resource-group-name 'mon-rg' --location 'France Central'" "gray"
else
    write_warning "Certains prérequis manquent encore."
    write_info "Installez les composants manquants puis relancez ce script avec --check-only"
fi

echo ""
write_color "📚 Ressources utiles:" "blue"
write_color "• Documentation Azure CLI: https://docs.microsoft.com/cli/azure/" "gray"
write_color "• Documentation Docker: https://docs.docker.com/" "gray"
write_color "• Azure Container Instances: https://docs.microsoft.com/azure/container-instances/" "gray"

echo ""
write_color "💡 Conseils:" "yellow"
write_color "• Le nom du registre de conteneurs doit être unique globalement" "gray"
write_color "• Choisissez une région Azure proche de vos utilisateurs" "gray"
write_color "• Les logs du conteneur sont accessibles via Azure CLI ou le portail Azure" "gray" 