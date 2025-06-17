#!/bin/bash

# Script de test pour vérifier les scripts Linux
# Ce script teste que tous les scripts bash sont syntaxiquement corrects

set -e

echo "🧪 Test des scripts Linux de déploiement Azure"
echo "=============================================="

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_script() {
    local script="$1"
    local description="$2"
    
    echo -n "Testing $description... "
    
    if [[ ! -f "$script" ]]; then
        echo -e "${RED}FAIL${NC} - File not found"
        return 1
    fi
    
    if [[ ! -x "$script" ]]; then
        echo -e "${YELLOW}WARN${NC} - Not executable, fixing..."
        chmod +x "$script"
    fi
    
    # Test syntax
    if bash -n "$script" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC}"
        return 0
    else
        echo -e "${RED}FAIL${NC} - Syntax error"
        return 1
    fi
}

# Test de tous les scripts
scripts=(
    "azure-setup.sh:Configuration et prérequis"
    "deploy-azure.sh:Déploiement principal"
    "azure-manage.sh:Gestion du déploiement"
    "azure-update-http.sh:Mise à jour HTTP"
    "azure-cleanup.sh:Nettoyage des ressources"
)

total=0
passed=0

for script_info in "${scripts[@]}"; do
    IFS=':' read -r script desc <<< "$script_info"
    ((total++))
    if test_script "$script" "$desc"; then
        ((passed++))
    fi
done

echo ""
echo "Résultats: $passed/$total tests passés"

if [[ $passed -eq $total ]]; then
    echo -e "${GREEN}✅ Tous les scripts sont prêts à être utilisés!${NC}"
    echo ""
    echo "Pour commencer:"
    echo "  ./azure-setup.sh --check-only"
    echo "  ./deploy-azure.sh --help"
else
    echo -e "${RED}❌ Certains scripts ont des problèmes${NC}"
    exit 1
fi

echo ""
echo "📚 Documentation disponible dans README_LINUX.md" 