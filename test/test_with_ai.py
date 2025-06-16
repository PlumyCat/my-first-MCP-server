#!/usr/bin/env python3
"""
Test du serveur MCP Weather avec un client IA
Ce script configure le serveur MCP pour être utilisé avec Claude ou OpenAI
"""

import json
import os
import subprocess
import sys
from pathlib import Path

print("🤖 Configuration MCP pour IA (Claude/OpenAI)")
print("=" * 50)


def check_docker_container():
    """Vérifie si le container Docker est actif"""
    try:
        result = subprocess.run(
            "docker ps --filter name=mcp-weather-server --format '{{.Names}}'",
            shell=True, capture_output=True, text=True
        )
        return "mcp-weather-server" in result.stdout
    except:
        return False


def create_mcp_config():
    """Crée la configuration MCP pour Claude Desktop"""

    # Chemin vers le workspace actuel
    workspace_path = Path.cwd().absolute()

    # Configuration MCP pour Claude Desktop
    mcp_config = {
        "mcpServers": {
            "weather-server": {
                "command": "python",
                "args": ["-m", "src.main"],
                "cwd": str(workspace_path),
                "env": {
                    "PYTHONPATH": str(workspace_path),
                    "PYTHONUNBUFFERED": "1"
                }
            }
        }
    }

    # Chemin de configuration Claude Desktop (Windows)
    claude_config_dir = Path.home() / "AppData" / "Roaming" / "Claude"
    claude_config_file = claude_config_dir / "claude_desktop_config.json"

    print(f"1. Configuration MCP pour Claude Desktop...")
    print(f"   Workspace: {workspace_path}")
    print(f"   Config file: {claude_config_file}")

    try:
        # Créer le répertoire si nécessaire
        claude_config_dir.mkdir(parents=True, exist_ok=True)

        # Lire la configuration existante ou créer une nouvelle
        existing_config = {}
        if claude_config_file.exists():
            try:
                with open(claude_config_file, 'r', encoding='utf-8') as f:
                    existing_config = json.load(f)
            except:
                pass

        # Fusionner les configurations
        if "mcpServers" not in existing_config:
            existing_config["mcpServers"] = {}

        existing_config["mcpServers"]["weather-server"] = mcp_config["mcpServers"]["weather-server"]

        # Écrire la configuration
        with open(claude_config_file, 'w', encoding='utf-8') as f:
            json.dump(existing_config, f, indent=2, ensure_ascii=False)

        print("   ✅ Configuration Claude Desktop mise à jour")
        return True

    except Exception as e:
        print(f"   ❌ Erreur configuration Claude: {e}")
        return False


def create_openai_config():
    """Crée un exemple de configuration pour OpenAI/autres clients MCP"""

    workspace_path = Path.cwd().absolute()

    config_example = {
        "name": "Weather MCP Server",
        "description": "Serveur MCP pour données météo factices",
        "command": ["python", "-m", "src.main"],
        "cwd": str(workspace_path),
        "env": {
            "PYTHONPATH": str(workspace_path),
            "PYTHONUNBUFFERED": "1"
        },
        "usage": {
            "tools": [
                {
                    "name": "get_weather",
                    "description": "Récupère les conditions météorologiques pour une ville",
                    "parameters": {
                        "city": "Nom de la ville (requis)",
                        "unit": "Unité de température: celsius ou fahrenheit (optionnel)"
                    },
                    "example": "get_weather(city='Paris', unit='celsius')"
                }
            ]
        }
    }

    config_file = Path("mcp_config_example.json")

    print(f"2. Configuration exemple pour autres clients MCP...")
    print(f"   Config file: {config_file}")

    try:
        with open(config_file, 'w', encoding='utf-8') as f:
            json.dump(config_example, f, indent=2, ensure_ascii=False)

        print("   ✅ Fichier de configuration exemple créé")
        return True

    except Exception as e:
        print(f"   ❌ Erreur création config exemple: {e}")
        return False


def test_local_server():
    """Test le serveur MCP en local"""
    print("3. Test du serveur MCP en local...")

    try:
        # Test d'import des modules
        sys.path.append('./src')
        from src.server import create_mcp_server
        from src.tools.weather import WeatherTool

        print("   ✅ Modules importés avec succès")

        # Test de création du serveur
        server = create_mcp_server()
        print("   ✅ Serveur MCP créé avec succès")

        # Test de l'outil weather
        import asyncio

        async def test_tool():
            tool = WeatherTool()
            result = await tool.execute("Paris", "celsius")
            return result

        result = asyncio.run(test_tool())
        if result["success"]:
            print("   ✅ Outil weather fonctionne")
            print(
                f"   📊 Exemple: {result['data']['city']} - {result['data']['temperature']}{result['data']['unit']}")
        else:
            print(f"   ❌ Erreur outil weather: {result.get('error')}")

        return True

    except Exception as e:
        print(f"   ❌ Erreur test local: {e}")
        return False


def show_usage_instructions():
    """Affiche les instructions d'utilisation"""
    print("\n📋 Instructions d'utilisation:")
    print("-" * 30)

    print("\n🔵 Avec Claude Desktop:")
    print("   1. Redémarrez Claude Desktop")
    print("   2. Le serveur 'weather-server' sera disponible")
    print("   3. Utilisez: 'Peux-tu me donner la météo de Paris ?'")

    print("\n🟠 Avec d'autres clients MCP:")
    print("   1. Utilisez la config dans 'mcp_config_example.json'")
    print("   2. Adaptez selon votre client MCP")

    print("\n🐳 Mode Docker:")
    docker_available = check_docker_container()
    if docker_available:
        print("   ✅ Container Docker actif")
        print("   💡 Le serveur fonctionne dans le container")
    else:
        print("   🔴 Container Docker inactif")
        print("   💡 Démarrez avec: docker-compose up -d")

    print("\n🛠️  Commandes utiles:")
    print("   • Test local: python test_with_ai.py")
    print("   • Test simple: python test_simple.py")
    print("   • Test MCP: python test_mcp_client.py")
    print("   • Logs Docker: docker logs mcp-weather-server")


def main():
    """Fonction principale"""

    # Test du serveur local
    local_ok = test_local_server()

    if local_ok:
        # Création des configurations
        claude_ok = create_mcp_config()
        openai_ok = create_openai_config()

        if claude_ok or openai_ok:
            print("\n🎉 Configuration terminée avec succès!")
        else:
            print("\n⚠️  Problèmes lors de la configuration")
    else:
        print("\n❌ Le serveur local ne fonctionne pas correctement")
        print("   Vérifiez l'installation des dépendances:")
        print("   pip install -r requirements.txt")

    # Instructions d'utilisation
    show_usage_instructions()

    print("\n" + "="*50)
    print("🏁 Configuration terminée!")


if __name__ == "__main__":
    main()
