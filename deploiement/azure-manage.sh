#!/bin/bash

# Script de gestion pour le serveur MCP Weather déployé sur Azure
# Version Linux du script azure-manage.ps1

set -e

# Variables par défaut
ACTION=""
RESOURCE_GROUP_NAME="mcp-weather-rg"
CONTAINER_INSTANCE_NAME="mcp-weather-server"
FOLLOW=false

# Fonction d'aide
show_help() {
    echo "🛠️  Gestionnaire Azure MCP Weather Server"
    echo "========================================="
    echo ""
    echo "Usage: $0 --action ACTION [OPTIONS]"
    echo ""
    echo "Actions disponibles:"
    echo "  status   - Affiche l'état du conteneur"
    echo "  logs     - Affiche les logs du conteneur"
    echo "  restart  - Redémarre le conteneur"
    echo "  stop     - Arrête le conteneur"
    echo "  start    - Démarre le conteneur"
    echo "  update   - Met à jour le conteneur avec une nouvelle image"
    echo "  delete   - Supprime complètement le déploiement"
    echo "  help     - Affiche cette aide"
    echo ""
    echo "Options:"
    echo "  --action ACTION                 Action à effectuer (obligatoire)"
    echo "  --resource-group-name NAME      Nom du groupe de ressources Azure (défaut: mcp-weather-rg)"
    echo "  --container-instance-name NAME  Nom de l'instance de conteneur (défaut: mcp-weather-server)"
    echo "  --follow                        Suit les logs en temps réel (pour l'action logs)"
    echo "  -h, --help                      Affiche cette aide"
    echo ""
    echo "Exemples d'utilisation:"
    echo "  $0 --action status"
    echo "  $0 --action logs --follow"
    echo "  $0 --action restart"
    echo "  $0 --action delete --resource-group-name 'mon-rg'"
}

# Traitement des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --action)
            ACTION="$2"
            shift 2
            ;;
        --resource-group-name)
            RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        --container-instance-name)
            CONTAINER_INSTANCE_NAME="$2"
            shift 2
            ;;
        --follow)
            FOLLOW=true
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

# Vérifier que l'action est fournie
if [[ -z "$ACTION" ]]; then
    echo "Erreur: L'action est obligatoire"
    show_help
    exit 1
fi

# Valider l'action
case "$ACTION" in
    "status"|"logs"|"restart"|"stop"|"start"|"delete"|"update"|"help")
        ;;
    *)
        echo "Erreur: Action '$ACTION' non reconnue"
        show_help
        exit 1
        ;;
esac

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

# Fonction pour tester la connexion Azure
test_azure_connection() {
    if az account show --output json &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Fonction pour tester si le conteneur existe
test_container_exists() {
    if az container show --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --output none 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Fonction pour afficher l'état du conteneur
get_container_status() {
    write_step "Récupération de l'état du conteneur..."
    
    if container_info=$(az container show --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --output json); then
        write_success "Informations du conteneur récupérées"
        echo ""
        write_color "📊 État du conteneur:" "green"
        write_color "=====================" "green"
        
        # Extraire les informations
        name=$(echo "$container_info" | jq -r '.name')
        state=$(echo "$container_info" | jq -r '.instanceView.currentState.state')
        start_time=$(echo "$container_info" | jq -r '.instanceView.currentState.startTime // "N/A"')
        cpu=$(echo "$container_info" | jq -r '.containers[0].resources.requests.cpu // "N/A"')
        memory=$(echo "$container_info" | jq -r '.containers[0].resources.requests.memoryInGB // "N/A"')
        ip=$(echo "$container_info" | jq -r '.ipAddress.ip // "N/A"')
        fqdn=$(echo "$container_info" | jq -r '.ipAddress.fqdn // "N/A"')
        restart_policy=$(echo "$container_info" | jq -r '.restartPolicy // "N/A"')
        resource_group=$(echo "$container_info" | jq -r '.resourceGroup // "N/A"')
        location=$(echo "$container_info" | jq -r '.location // "N/A"')
        
        write_color "  • Nom: $name" "white"
        write_color "  • État: $state" "white"
        write_color "  • Heure de démarrage: $start_time" "white"
        write_color "  • CPU: $cpu cœurs" "white"
        write_color "  • Mémoire: $memory GB" "white"
        write_color "  • Adresse IP: $ip" "white"
        
        if [[ "$fqdn" != "N/A" && "$fqdn" != "null" ]]; then
            write_color "  • FQDN: $fqdn" "white"
            write_color "  • URL: http://$fqdn:8000" "white"
        fi
        
        write_color "  • Politique de redémarrage: $restart_policy" "white"
        write_color "  • Groupe de ressources: $resource_group" "white"
        write_color "  • Région: $location" "white"
        
        # Afficher les événements récents
        events=$(echo "$container_info" | jq -r '.instanceView.events[]? | "\(.firstTimestamp): \(.message)"' 2>/dev/null)
        if [[ -n "$events" ]]; then
            echo ""
            write_color "📋 Événements récents:" "yellow"
            echo "$events" | while IFS= read -r event; do
                write_color "  • $event" "gray"
            done
        fi
        
        return 0
    else
        write_error "Erreur lors de la récupération de l'état"
        return 1
    fi
}

# Fonction pour récupérer les logs
get_container_logs() {
    write_step "Récupération des logs du conteneur..."
    
    if [[ "$FOLLOW" == "true" ]]; then
        write_info "Suivi des logs en temps réel (Ctrl+C pour arrêter)..."
        az container logs --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --follow
    else
        if logs=$(az container logs --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME"); then
            write_success "Logs récupérés"
            echo ""
            write_color "📜 Logs du conteneur:" "green"
            write_color "====================" "green"
            echo "$logs"
        else
            write_error "Erreur lors de la récupération des logs"
            return 1
        fi
    fi
    return 0
}

# Fonction pour redémarrer le conteneur
restart_container() {
    write_step "Redémarrage du conteneur..."
    
    if az container restart --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --output none; then
        write_success "Conteneur redémarré avec succès"
        
        # Attendre un peu et afficher le nouvel état
        sleep 5
        get_container_status
        return 0
    else
        write_error "Erreur lors du redémarrage"
        return 1
    fi
}

# Fonction pour arrêter le conteneur
stop_container() {
    write_step "Arrêt du conteneur..."
    
    if az container stop --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --output none; then
        write_success "Conteneur arrêté avec succès"
        return 0
    else
        write_error "Erreur lors de l'arrêt"
        return 1
    fi
}

# Fonction pour démarrer le conteneur
start_container() {
    write_step "Démarrage du conteneur..."
    
    if az container start --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --output none; then
        write_success "Conteneur démarré avec succès"
        
        # Attendre un peu et afficher l'état
        sleep 5
        get_container_status
        return 0
    else
        write_error "Erreur lors du démarrage"
        return 1
    fi
}

# Fonction pour mettre à jour le conteneur
update_container() {
    write_warning "La mise à jour nécessite de reconstruire et redéployer l'image."
    write_info "Cette opération va:"
    write_color "  1. Reconstruire l'image Docker localement" "gray"
    write_color "  2. La pousser vers Azure Container Registry" "gray"
    write_color "  3. Redémarrer le conteneur avec la nouvelle image" "gray"
    
    read -p "Voulez-vous continuer? (o/N): " confirmation
    if [[ "$confirmation" != "o" && "$confirmation" != "O" && "$confirmation" != "oui" ]]; then
        write_warning "Mise à jour annulée"
        return 1
    fi
    
    write_info "Pour effectuer la mise à jour, veuillez exécuter le script de déploiement:"
    write_color "./deploy-azure.sh --container-registry-name 'votre-registre' --resource-group-name '$RESOURCE_GROUP_NAME' --container-instance-name '$CONTAINER_INSTANCE_NAME'" "yellow"
    
    return 0
}

# Fonction pour supprimer le déploiement
remove_deployment() {
    write_warning "⚠️  ATTENTION: Cette action va supprimer COMPLÈTEMENT le déploiement!"
    write_color "Cela inclut:" "red"
    write_color "  • L'instance de conteneur" "red"
    write_color "  • Le groupe de ressources (si vide)" "red"
    write_color "  • Toutes les données associées" "red"
    
    read -p "Êtes-vous sûr de vouloir supprimer le déploiement? Tapez 'SUPPRIMER' pour confirmer: " confirmation
    if [[ "$confirmation" != "SUPPRIMER" ]]; then
        write_warning "Suppression annulée par l'utilisateur."
        return 1
    fi
    
    write_step "Suppression de l'instance de conteneur..."
    if az container delete --resource-group "$RESOURCE_GROUP_NAME" --name "$CONTAINER_INSTANCE_NAME" --yes --output none; then
        write_success "Instance de conteneur supprimée"
        
        # Vérifier si le groupe de ressources est vide
        write_step "Vérification du groupe de ressources..."
        if resources=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" --output json); then
            resource_count=$(echo "$resources" | jq length)
            if [[ "$resource_count" -eq 0 ]]; then
                write_info "Le groupe de ressources est vide."
                read -p "Voulez-vous également supprimer le groupe de ressources '$RESOURCE_GROUP_NAME'? (o/N): " rg_confirmation
                if [[ "$rg_confirmation" == "o" || "$rg_confirmation" == "O" || "$rg_confirmation" == "oui" ]]; then
                    if az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait; then
                        write_success "Suppression du groupe de ressources initiée"
                    else
                        write_warning "Erreur lors de la suppression du groupe de ressources"
                    fi
                fi
            else
                write_info "Le groupe de ressources contient encore $resource_count ressource(s)"
            fi
        fi
        
        return 0
    else
        write_error "Erreur lors de la suppression"
        return 1
    fi
}

# Afficher l'aide si demandé
if [[ "$ACTION" == "help" ]]; then
    show_help
    exit 0
fi

# Vérifier la connexion Azure
if ! test_azure_connection; then
    write_error "Vous n'êtes pas connecté à Azure. Exécutez 'az login' pour vous connecter."
    exit 1
fi

# Vérifier si le conteneur existe
if ! test_container_exists; then
    write_error "Le conteneur '$CONTAINER_INSTANCE_NAME' n'existe pas dans le groupe de ressources '$RESOURCE_GROUP_NAME'"
    write_info "Vérifiez les noms ou déployez d'abord le conteneur avec:"
    write_color "./deploy-azure.sh --container-registry-name 'votre-registre'" "gray"
    exit 1
fi

# Exécuter l'action demandée
case "$ACTION" in
    "status")
        get_container_status
        ;;
    "logs")
        get_container_logs
        ;;
    "restart")
        restart_container
        ;;
    "stop")
        stop_container
        ;;
    "start")
        start_container
        ;;
    "update")
        update_container
        ;;
    "delete")
        remove_deployment
        ;;
esac 