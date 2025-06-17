#!/bin/bash

# Script de déploiement Azure pour le serveur MCP Weather
# Version Linux du script deploy-azure.ps1

set -e

# Variables par défaut
RESOURCE_GROUP_NAME="mcp-weather-rg"
LOCATION="francecentral"
CONTAINER_REGISTRY_NAME=""
CONTAINER_INSTANCE_NAME="mcp-weather-server"
IMAGE_TAG="latest"

# Fonction d'aide
show_help() {
    echo "Usage: $0 --container-registry-name NAME [OPTIONS]"
    echo ""
    echo "Options obligatoires:"
    echo "  --container-registry-name NAME  Nom du registre de conteneurs Azure (doit être unique globalement)"
    echo ""
    echo "Options facultatives:"
    echo "  --resource-group-name NAME      Nom du groupe de ressources Azure (défaut: mcp-weather-rg)"
    echo "  --location LOCATION             Région Azure pour le déploiement (défaut: francecentral)"
    echo "  --container-instance-name NAME  Nom de l'instance de conteneur (défaut: mcp-weather-server)"
    echo "  --image-tag TAG                 Tag de l'image Docker (défaut: latest)"
    echo "  -h, --help                      Affiche cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 --container-registry-name 'monregistreunique123'"
    echo "  $0 --container-registry-name 'monregistre' --resource-group-name 'mon-rg' --location 'westeurope'"
}

# Traitement des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group-name)
            RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --container-registry-name)
            CONTAINER_REGISTRY_NAME="$2"
            shift 2
            ;;
        --container-instance-name)
            CONTAINER_INSTANCE_NAME="$2"
            shift 2
            ;;
        --image-tag)
            IMAGE_TAG="$2"
            shift 2
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

# Vérifier que le nom du registre est fourni
if [[ -z "$CONTAINER_REGISTRY_NAME" ]]; then
    echo "Erreur: Le nom du registre de conteneurs est obligatoire"
    show_help
    exit 1
fi

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
        "white") echo -e "\033[97m$message\033[0m" ;;
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

# Vérification des prérequis
write_color "🌤️  Déploiement du serveur MCP Weather sur Azure" "magenta"
write_color "=================================================" "magenta"

write_step "Vérification des prérequis..."

# Vérifier si Azure CLI est installé
if command -v az &> /dev/null; then
    if az_version=$(az version --output json 2>/dev/null | jq -r '."azure-cli"' 2>/dev/null); then
        write_success "Azure CLI version $az_version détecté"
    else
        write_error "Azure CLI ne fonctionne pas correctement"
        exit 1
    fi
else
    write_error "Azure CLI n'est pas installé. Veuillez l'installer depuis https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Vérifier si Docker est installé
if command -v docker &> /dev/null; then
    if docker_version=$(docker --version 2>/dev/null); then
        write_success "Docker détecté: $docker_version"
    else
        write_error "Docker ne fonctionne pas correctement"
        exit 1
    fi
else
    write_error "Docker n'est pas installé. Veuillez l'installer depuis https://docs.docker.com/get-docker"
    exit 1
fi

# Vérifier si l'utilisateur est connecté à Azure
write_step "Vérification de la connexion Azure..."
if account_info=$(az account show --output json 2>/dev/null); then
    user_name=$(echo "$account_info" | jq -r '.user.name')
    subscription_name=$(echo "$account_info" | jq -r '.name')
    subscription_id=$(echo "$account_info" | jq -r '.id')
    write_success "Connecté à Azure avec le compte: $user_name"
    write_color "Abonnement actuel: $subscription_name ($subscription_id)" "yellow"
else
    write_error "Vous n'êtes pas connecté à Azure. Exécutez 'az login' pour vous connecter."
    exit 1
fi

# Demander confirmation pour continuer
echo ""
read -p "Voulez-vous continuer avec cet abonnement? (o/N): " confirmation
if [[ "$confirmation" != "o" && "$confirmation" != "O" && "$confirmation" != "oui" ]]; then
    write_warning "Déploiement annulé par l'utilisateur."
    exit 0
fi

# Variables dérivées
ACR_LOGIN_SERVER="$CONTAINER_REGISTRY_NAME.azurecr.io"
IMAGE_NAME="$ACR_LOGIN_SERVER/mcp-weather-server"
IMAGE_FULL_NAME="$IMAGE_NAME:$IMAGE_TAG"

echo ""
write_color "📋 Configuration du déploiement:" "yellow"
write_color "  • Groupe de ressources: $RESOURCE_GROUP_NAME" "white"
write_color "  • Région: $LOCATION" "white"
write_color "  • Registre de conteneurs: $CONTAINER_REGISTRY_NAME" "white"
write_color "  • Instance de conteneur: $CONTAINER_INSTANCE_NAME" "white"
write_color "  • Image: $IMAGE_FULL_NAME" "white"

# Étape 1: Créer le groupe de ressources
write_step "Création du groupe de ressources '$RESOURCE_GROUP_NAME'..."
rg_exists=$(az group exists --name "$RESOURCE_GROUP_NAME" --output tsv)
if [[ "$rg_exists" == "true" ]]; then
    write_success "Le groupe de ressources '$RESOURCE_GROUP_NAME' existe déjà"
else
    if az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --output none; then
        write_success "Groupe de ressources '$RESOURCE_GROUP_NAME' créé avec succès"
    else
        write_error "Erreur lors de la création du groupe de ressources"
        exit 1
    fi
fi

# Étape 2: Créer Azure Container Registry
write_step "Création d'Azure Container Registry '$CONTAINER_REGISTRY_NAME'..."
if az acr show --name "$CONTAINER_REGISTRY_NAME" --resource-group "$RESOURCE_GROUP_NAME" --output none 2>/dev/null; then
    write_success "Le registre de conteneurs '$CONTAINER_REGISTRY_NAME' existe déjà"
else
    if az acr create --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_REGISTRY_NAME" --sku Basic --admin-enabled true --output none; then
        write_success "Registre de conteneurs '$CONTAINER_REGISTRY_NAME' créé avec succès"
    else
        write_error "Erreur lors de la création du registre de conteneurs"
        exit 1
    fi
fi

# Étape 3: Se connecter au registre de conteneurs
write_step "Connexion au registre de conteneurs..."
if az acr login --name "$CONTAINER_REGISTRY_NAME"; then
    write_success "Connexion au registre de conteneurs réussie"
else
    write_error "Erreur lors de la connexion au registre de conteneurs"
    exit 1
fi

# Étape 4: Construire et pousser l'image Docker
write_step "Construction de l'image Docker..."

# Vérifier que le Dockerfile existe
if [[ ! -f "Dockerfile" ]]; then
    write_error "Dockerfile non trouvé dans le répertoire courant"
    exit 1
fi

if docker build -t "$IMAGE_NAME" .; then
    write_success "Image Docker construite avec succès"
else
    write_error "Erreur lors de la construction de l'image Docker"
    exit 1
fi

write_step "Ajout du tag et push vers Azure Container Registry..."
if docker tag "$IMAGE_NAME" "$IMAGE_FULL_NAME" && docker push "$IMAGE_FULL_NAME"; then
    write_success "Image poussée vers ACR avec succès"
else
    write_error "Erreur lors du push vers ACR"
    exit 1
fi

# Étape 5: Obtenir les identifiants du registre
write_step "Récupération des identifiants du registre..."
if acr_credentials=$(az acr credential show --name "$CONTAINER_REGISTRY_NAME" --output json); then
    acr_username=$(echo "$acr_credentials" | jq -r '.username')
    acr_password=$(echo "$acr_credentials" | jq -r '.passwords[0].value')
    write_success "Identifiants du registre récupérés"
else
    write_error "Erreur lors de la récupération des identifiants"
    exit 1
fi

# Étape 6: Déployer sur Azure Container Instances
write_step "Déploiement sur Azure Container Instances..."

# Supprimer l'instance existante si elle existe
if az container show --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --output none 2>/dev/null; then
    write_warning "Instance de conteneur existante détectée. Suppression..."
    if az container delete --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --yes --output none; then
        write_success "Instance existante supprimée"
    else
        write_warning "Erreur lors de la suppression de l'instance existante"
    fi
fi

# Créer la nouvelle instance
if az container create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$CONTAINER_INSTANCE_NAME" \
    --image "$IMAGE_FULL_NAME" \
    --registry-login-server "$ACR_LOGIN_SERVER" \
    --registry-username "$acr_username" \
    --registry-password "$acr_password" \
    --cpu 1 \
    --memory 1 \
    --os-type Linux \
    --restart-policy Always \
    --environment-variables PYTHONUNBUFFERED=1 PYTHONPATH=/app \
    --ports 8000 \
    --protocol TCP \
    --dns-name-label "$CONTAINER_INSTANCE_NAME" \
    --output none; then
    write_success "Instance de conteneur déployée avec succès"
else
    write_error "Erreur lors du déploiement sur ACI"
    exit 1
fi

# Étape 7: Obtenir les informations de déploiement
write_step "Récupération des informations de déploiement..."

# Attendre un peu que le conteneur soit complètement déployé
sleep 10

if container_info=$(az container show --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --output json); then
    container_state=$(echo "$container_info" | jq -r '.instanceView.currentState.state')
    container_ip=$(echo "$container_info" | jq -r '.ipAddress.ip // "N/A"')
    container_fqdn=$(echo "$container_info" | jq -r '.ipAddress.fqdn // "N/A"')
    
    echo ""
    write_color "🎉 Déploiement terminé avec succès!" "green"
    write_color "====================================" "green"
    
    echo ""
    write_color "📋 Informations du déploiement:" "yellow"
    write_color "  • Nom du conteneur: $CONTAINER_INSTANCE_NAME" "white"
    write_color "  • État: $container_state" "white"
    write_color "  • Adresse IP: $container_ip" "white"
    
    if [[ "$container_fqdn" != "N/A" && "$container_fqdn" != "null" ]]; then
        write_color "  • FQDN: $container_fqdn" "white"
        write_color "  • URL: http://$container_fqdn:8000" "white"
    fi
    
    write_color "  • Groupe de ressources: $RESOURCE_GROUP_NAME" "white"
    write_color "  • Région: $LOCATION" "white"
    
    echo ""
    write_color "🛠️  Commandes utiles:" "blue"
    write_color "• Voir les logs:" "white"
    write_color "  az container logs --resource-group $RESOURCE_GROUP_NAME --name $CONTAINER_INSTANCE_NAME" "gray"
    write_color "• Voir l'état:" "white"
    write_color "  az container show --resource-group $RESOURCE_GROUP_NAME --name $CONTAINER_INSTANCE_NAME" "gray"
    write_color "• Redémarrer:" "white"
    write_color "  az container restart --resource-group $RESOURCE_GROUP_NAME --name $CONTAINER_INSTANCE_NAME" "gray"
    
    echo ""
    write_color "🧪 Test du déploiement:" "blue"
    if [[ "$container_fqdn" != "N/A" && "$container_fqdn" != "null" ]]; then
        write_color "• Test HTTP (si serveur HTTP activé):" "white"
        write_color "  curl http://$container_fqdn:8000/health" "gray"
    fi
    write_color "• Utiliser les scripts de test:" "white"
    write_color "  python test/test_azure_deployment.py" "gray"
    
    echo ""
    write_color "📚 Gestion du déploiement:" "blue"
    write_color "• Utiliser le script de gestion:" "white"
    write_color "  ./azure-manage.sh --action status" "gray"
    write_color "• Nettoyer les ressources:" "white"
    write_color "  ./azure-cleanup.sh --resource-group-name $RESOURCE_GROUP_NAME" "gray"
    
else
    write_error "Impossible de récupérer les informations du conteneur"
    exit 1
fi

echo ""
write_color "✨ Le serveur MCP Weather est maintenant déployé sur Azure!" "green" 