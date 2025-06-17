#!/bin/bash

# Script de nettoyage pour les ressources Azure MCP Weather
# Version Linux du script azure-cleanup.ps1

set -e

# Variables par défaut
RESOURCE_GROUP_NAME="mcp-weather-rg"
CONTAINER_REGISTRY_NAME=""
FORCE=false

# Fonction d'aide
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --resource-group-name NAME    Nom du groupe de ressources à nettoyer (défaut: mcp-weather-rg)"
    echo "  --container-registry-name NAME Nom du registre de conteneurs à supprimer"
    echo "  --force                       Force la suppression sans demander de confirmation"
    echo "  -h, --help                   Affiche cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 --resource-group-name 'mcp-weather-rg'"
    echo "  $0 --resource-group-name 'mcp-weather-rg' --force"
}

# Traitement des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group-name)
            RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        --container-registry-name)
            CONTAINER_REGISTRY_NAME="$2"
            shift 2
            ;;
        --force)
            FORCE=true
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

# En-tête
write_color "🧹 Nettoyage des ressources Azure MCP Weather" "magenta"
write_color "=============================================" "magenta"

# Vérifier la connexion Azure
write_step "Vérification de la connexion Azure..."
if account_info=$(az account show --output json 2>/dev/null); then
    user_name=$(echo "$account_info" | jq -r '.user.name')
    subscription_name=$(echo "$account_info" | jq -r '.name')
    write_success "Connecté à Azure avec: $user_name"
    write_color "Abonnement: $subscription_name" "yellow"
else
    write_error "Vous n'êtes pas connecté à Azure. Exécutez 'az login' pour vous connecter."
    exit 1
fi

# Vérifier si le groupe de ressources existe
write_step "Vérification du groupe de ressources '$RESOURCE_GROUP_NAME'..."
rg_exists=$(az group exists --name "$RESOURCE_GROUP_NAME" --output tsv)

if [[ "$rg_exists" == "false" ]]; then
    write_warning "Le groupe de ressources '$RESOURCE_GROUP_NAME' n'existe pas."
    write_info "Rien à nettoyer."
    exit 0
fi

write_success "Groupe de ressources '$RESOURCE_GROUP_NAME' trouvé"

# Lister les ressources dans le groupe
write_step "Analyse des ressources dans le groupe '$RESOURCE_GROUP_NAME'..."
if resources=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" --output json 2>/dev/null); then
    resource_count=$(echo "$resources" | jq length)
    
    if [[ "$resource_count" -eq 0 ]]; then
        write_warning "Aucune ressource trouvée dans le groupe '$RESOURCE_GROUP_NAME'"
    else
        echo ""
        write_color "📋 Ressources trouvées:" "yellow"
        echo "$resources" | jq -r '.[] | "  • \(.name) (\(.type))"'
    fi
else
    write_warning "Impossible de lister les ressources"
fi

# Demander confirmation si pas en mode Force
if [[ "$FORCE" != "true" ]]; then
    echo ""
    write_color "⚠️  ATTENTION: Cette action va supprimer TOUTES les ressources!" "red"
    write_color "Cela inclut:" "red"
    write_color "  • Toutes les instances de conteneurs" "red"
    write_color "  • Le registre de conteneurs (et toutes ses images)" "red"
    write_color "  • Le groupe de ressources complet" "red"
    write_color "  • Toutes les données associées" "red"
    
    echo ""
    read -p "Êtes-vous sûr de vouloir supprimer le groupe de ressources '$RESOURCE_GROUP_NAME'? Tapez 'SUPPRIMER' pour confirmer: " confirmation
    if [[ "$confirmation" != "SUPPRIMER" ]]; then
        write_warning "Nettoyage annulé par l'utilisateur."
        exit 0
    fi
fi

# Supprimer le groupe de ressources
write_step "Suppression du groupe de ressources '$RESOURCE_GROUP_NAME'..."
write_info "Cette opération peut prendre plusieurs minutes..."

if az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait; then
    write_success "Suppression du groupe de ressources initiée (en arrière-plan)"
    
    # Attendre un peu et vérifier le statut
    write_info "Vérification du statut de suppression..."
    sleep 5
    
    delete_status=$(az group exists --name "$RESOURCE_GROUP_NAME" --output tsv)
    if [[ "$delete_status" == "false" ]]; then
        write_success "Groupe de ressources supprimé avec succès"
    else
        write_info "Suppression en cours... Vous pouvez vérifier le statut avec:"
        write_color "  az group show --name $RESOURCE_GROUP_NAME --query 'properties.provisioningState'" "gray"
    fi
else
    write_error "Erreur lors de la suppression"
    exit 1
fi

# Nettoyage local des images Docker (optionnel)
write_step "Nettoyage des images Docker locales..."
if command -v docker &> /dev/null; then
    if [[ -n "$CONTAINER_REGISTRY_NAME" ]]; then
        image_name="$CONTAINER_REGISTRY_NAME.azurecr.io/mcp-weather-server"
        
        # Supprimer les images locales
        if local_images=$(docker images --filter "reference=$image_name*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null); then
            if [[ -n "$local_images" ]]; then
                write_info "Suppression des images Docker locales..."
                while IFS= read -r image; do
                    if docker rmi "$image" --force 2>/dev/null; then
                        write_color "  • Image supprimée: $image" "gray"
                    fi
                done <<< "$local_images"
            fi
        fi
    fi
    
    # Nettoyage général Docker
    write_info "Nettoyage général Docker..."
    if docker system prune -f 2>/dev/null; then
        write_success "Images Docker locales nettoyées"
    fi
else
    write_warning "Docker non trouvé, nettoyage Docker ignoré"
fi

# Résumé final
echo ""
write_color "🎉 Nettoyage terminé!" "green"
write_color "=====================" "green"
write_color "✅ Groupe de ressources '$RESOURCE_GROUP_NAME' supprimé" "green"
write_color "✅ Images Docker locales nettoyées" "green"

echo ""
write_color "💡 Prochaines étapes:" "yellow"
write_color "• Vous pouvez maintenant relancer le déploiement avec:" "white"
write_color "  ./deploy-azure.sh --container-registry-name 'nouveau-nom-unique'" "gray"
write_color "• Ou vérifier les prérequis avec:" "white"
write_color "  ./azure-setup.sh --check-only" "gray"

echo ""
write_color "📊 Vérification du statut:" "blue"
write_color "• Vérifier que le groupe est supprimé:" "white"
write_color "  az group exists --name $RESOURCE_GROUP_NAME" "gray"
write_color "• Lister tous vos groupes de ressources:" "white"
write_color "  az group list --output table" "gray" 