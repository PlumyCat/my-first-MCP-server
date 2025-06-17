#!/bin/bash

# Met à jour le déploiement Azure pour utiliser le serveur HTTP
# Version Linux du script azure-update-http.ps1

set -e

# Variables par défaut
RESOURCE_GROUP="mcp-weather-rg"
CONTAINER_NAME="mcp-weather-server"
REGISTRY_NAME="mcpweatheracr3590"
IMAGE_TAG="http"

# Fonction d'aide
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --resource-group NAME     Nom du groupe de ressources (défaut: mcp-weather-rg)"
    echo "  --container-name NAME     Nom du conteneur (défaut: mcp-weather-server)"
    echo "  --registry-name NAME      Nom du registre ACR (défaut: mcpweatheracr3590)"
    echo "  --image-tag TAG           Tag de l'image (défaut: http)"
    echo "  -h, --help               Affiche cette aide"
    echo ""
    echo "Ce script met à jour le container Azure existant pour utiliser le serveur HTTP"
    echo "au lieu du serveur stdio, permettant les tests via HTTP/REST."
}

# Traitement des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --container-name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --registry-name)
            REGISTRY_NAME="$2"
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

echo "🔄 MISE À JOUR DÉPLOIEMENT AZURE VERS HTTP"
echo "=" | head -c 50; echo

# Vérifier Azure CLI
if command -v az &> /dev/null; then
    if az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null); then
        write_color "✅ Azure CLI version: $az_version" "green"
    else
        write_color "❌ Azure CLI ne fonctionne pas correctement" "red"
        exit 1
    fi
else
    write_color "❌ Azure CLI non trouvé" "red"
    exit 1
fi

# Vérifier la connexion Azure
if account=$(az account show --query "name" -o tsv 2>/dev/null); then
    write_color "✅ Connecté à Azure: $account" "green"
else
    write_color "❌ Non connecté à Azure" "red"
    write_color "💡 Connectez-vous avec: az login" "yellow"
    exit 1
fi

# Vérifier si le container existe
write_color "🔍 Vérification du container existant..." "yellow"
if container_state=$(az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --query "instanceView.state" -o tsv 2>/dev/null); then
    write_color "✅ Container trouvé (État: $container_state)" "green"
else
    write_color "❌ Container non trouvé" "red"
    exit 1
fi

# Construire la nouvelle image HTTP
write_color "🔨 Construction de l'image HTTP..." "yellow"
write_color "   📄 Utilisation de Dockerfile.http" "white"

# Vérifier si Dockerfile.http existe
if [[ ! -f "Dockerfile.http" ]]; then
    write_color "❌ Dockerfile.http non trouvé" "red"
    exit 1
fi

# Construire l'image dans Azure Container Registry
if az acr build --registry "$REGISTRY_NAME" --image "mcp-weather-server:$IMAGE_TAG" --file Dockerfile.http .; then
    write_color "✅ Image HTTP construite avec succès" "green"
else
    write_color "❌ Échec de construction de l'image" "red"
    exit 1
fi

# Arrêter le container existant
write_color "🛑 Arrêt du container existant..." "yellow"
if az container stop --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" 2>/dev/null; then
    write_color "✅ Container arrêté" "green"
else
    write_color "⚠️ Erreur lors de l'arrêt (peut être déjà arrêté)" "yellow"
fi

# Supprimer le container existant
write_color "🗑️ Suppression du container existant..." "yellow"
if az container delete --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --yes 2>/dev/null; then
    write_color "✅ Container supprimé" "green"
else
    write_color "⚠️ Erreur lors de la suppression" "yellow"
fi

# Attendre un peu
write_color "⏳ Attente 10 secondes..." "yellow"
sleep 10

# Redéployer avec la nouvelle image HTTP
write_color "🚀 Redéploiement avec serveur HTTP..." "yellow"

# Récupérer les variables d'environnement du fichier .env
env_vars=()
if [[ -f ".env" ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^#][^=]+)=(.+)$ ]]; then
            name="${BASH_REMATCH[1]// /}"
            value="${BASH_REMATCH[2]}"
            
            # Ajouter seulement les variables nécessaires
            case "$name" in
                "OPENWEATHER_API_KEY"|"AZURE_AD_TENANT_ID"|"AZURE_AD_CLIENT_ID"|"AZURE_AD_CLIENT_SECRET")
                    env_vars+=("$name=$value")
                    ;;
            esac
        fi
    done < .env
fi

if [[ ${#env_vars[@]} -eq 0 ]]; then
    write_color "⚠️ Aucune variable d'environnement trouvée dans .env" "yellow"
fi

# Récupérer le mot de passe du registre
registry_password=$(az acr credential show --name "$REGISTRY_NAME" --query "passwords[0].value" -o tsv)

# Construire la commande de déploiement
deploy_cmd=(
    "az" "container" "create"
    "--resource-group" "$RESOURCE_GROUP"
    "--name" "$CONTAINER_NAME"
    "--image" "$REGISTRY_NAME.azurecr.io/mcp-weather-server:$IMAGE_TAG"
    "--registry-login-server" "$REGISTRY_NAME.azurecr.io"
    "--registry-username" "$REGISTRY_NAME"
    "--registry-password" "$registry_password"
    "--dns-name-label" "$CONTAINER_NAME"
    "--ports" "8000"
    "--protocol" "TCP"
    "--os-type" "Linux"
    "--cpu" "1"
    "--memory" "1.5"
)

# Ajouter les variables d'environnement
for env_var in "${env_vars[@]}"; do
    deploy_cmd+=("--environment-variables" "$env_var")
done

write_color "   🔧 Déploiement en cours..." "white"
if "${deploy_cmd[@]}"; then
    write_color "✅ Container redéployé avec succès" "green"
else
    write_color "❌ Échec du redéploiement" "red"
    exit 1
fi

# Attendre que le container soit prêt
write_color "⏳ Attente du démarrage du container..." "yellow"
max_attempts=12
attempt=0

while [[ $attempt -lt $max_attempts ]]; do
    sleep 10
    ((attempt++))
    
    if state=$(az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --query "instanceView.state" -o tsv 2>/dev/null); then
        echo "   Tentative $attempt/$max_attempts - État: $state"
        
        if [[ "$state" == "Running" ]]; then
            break
        fi
    else
        echo "   Tentative $attempt/$max_attempts - Vérification..."
    fi
done

if [[ $attempt -ge $max_attempts ]]; then
    write_color "⚠️ Timeout - vérifiez manuellement l'état du container" "yellow"
else
    write_color "✅ Container en cours d'exécution" "green"
fi

# Afficher les informations de connexion
echo ""
write_color "📋 INFORMATIONS DE CONNEXION" "cyan"
echo "=" | head -c 40; echo

if container_info=$(az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --query "{fqdn: ipAddress.fqdn, ip: ipAddress.ip, state: instanceView.state}" -o json); then
    fqdn=$(echo "$container_info" | jq -r '.fqdn // "N/A"')
    ip=$(echo "$container_info" | jq -r '.ip // "N/A"')
    state=$(echo "$container_info" | jq -r '.state // "N/A"')
    
    if [[ "$fqdn" != "N/A" && "$fqdn" != "null" ]]; then
        url="https://$fqdn:8000"
        
        write_color "🌐 URL du serveur: $url" "green"
        write_color "🔗 Health check: $url/health" "green"
        write_color "🛠️ API MCP: $url/mcp" "green"
        write_color "📊 État: $state" "green"
        
        # Mettre à jour le fichier .env avec la nouvelle URL
        if [[ -f ".env" ]]; then
            # Créer un fichier temporaire
            temp_file=$(mktemp)
            url_updated=false
            
            while IFS= read -r line; do
                if [[ "$line" =~ ^AZURE_SERVER_URL= ]]; then
                    echo "AZURE_SERVER_URL=$url" >> "$temp_file"
                    url_updated=true
                else
                    echo "$line" >> "$temp_file"
                fi
            done < .env
            
            if [[ "$url_updated" == "false" ]]; then
                echo "AZURE_SERVER_URL=$url" >> "$temp_file"
            fi
            
            mv "$temp_file" .env
            write_color "✅ Fichier .env mis à jour avec la nouvelle URL" "green"
        fi
    fi
else
    write_color "⚠️ Impossible de récupérer les informations du container" "yellow"
fi

# Test de connectivité
echo ""
write_color "🧪 TEST DE CONNECTIVITÉ" "cyan"
echo "=" | head -c 30; echo

if [[ "$fqdn" != "N/A" && "$fqdn" != "null" ]]; then
    health_url="https://$fqdn:8000/health"
    write_color "🔍 Test de $health_url..." "white"
    
    # Attendre un peu plus pour que le serveur soit prêt
    sleep 5
    
    if response=$(curl -s --max-time 10 "$health_url" 2>/dev/null); then
        if echo "$response" | jq -e '.status == "healthy"' >/dev/null 2>&1; then
            write_color "✅ Serveur HTTP accessible et fonctionnel!" "green"
            write_color "🎉 Mise à jour réussie - vous pouvez maintenant tester avec:" "green"
            write_color "   python test/test_azure_deployment.py" "yellow"
        else
            write_color "⚠️ Serveur accessible mais réponse inattendue" "yellow"
        fi
    else
        write_color "⚠️ Test de connectivité échoué" "yellow"
        write_color "💡 Le serveur peut encore être en cours de démarrage" "yellow"
    fi
fi 