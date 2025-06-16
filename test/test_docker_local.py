#!/usr/bin/env python3
"""
Test du serveur MCP dans un container Docker local
Teste l'intégration : Docker Container -> Azure OpenAI/Claude API
"""

import os
import asyncio
import json
import time
import requests
import subprocess
from typing import Dict, Any, List
from dotenv import load_dotenv

# Charger les variables d'environnement
load_dotenv()

if __name__ == "__main__":
    print("🐳 TEST SERVEUR MCP DOCKER LOCAL")
    print("=" * 50)

# Vérifier Docker
try:
    result = subprocess.run(['docker', '--version'],
                            capture_output=True, text=True)
    if result.returncode == 0:
        print(f"✅ Docker disponible: {result.stdout.strip()}")
    else:
        print("❌ Docker non disponible")
        exit(1)
except FileNotFoundError:
    print("❌ Docker non installé")
    exit(1)

# Configuration
DOCKER_IMAGE = "mcp-weather-server"
DOCKER_PORT = 8000
LOCAL_URL = f"http://localhost:{DOCKER_PORT}"

# Vérifier les APIs optionnelles
has_azure_openai = all([
    os.getenv('AZURE_OPENAI_API_KEY'),
    os.getenv('AZURE_OPENAI_ENDPOINT'),
    os.getenv('AZURE_OPENAI_DEPLOYMENT_NAME')
])

has_claude = bool(os.getenv('ANTHROPIC_API_KEY'))

if not has_azure_openai and not has_claude:
    print("⚠️ Aucune API IA configurée (Azure OpenAI ou Claude)")
    print("💡 Le test se limitera aux appels MCP directs")

try:
    if has_azure_openai:
        import openai
        print("✅ Librairie OpenAI importée")
    if has_claude:
        import anthropic
        print("✅ Librairie Anthropic importée")
except ImportError as e:
    print(f"❌ Librairie manquante: {e}")
    print("💡 Installez avec: pip install openai anthropic")


class DockerMCPManager:
    """Gestionnaire du container Docker MCP"""

    def __init__(self):
        self.container_name = "mcp-weather-test"
        self.container_id = None
        self.is_running = False

    async def build_image(self) -> bool:
        """Construit l'image Docker"""
        print("🔨 Construction de l'image Docker...")

        try:
            # Vérifier si Dockerfile.http existe, sinon utiliser Dockerfile
            dockerfile = "Dockerfile.http" if os.path.exists(
                "Dockerfile.http") else "Dockerfile"
            print(f"   📄 Utilisation de {dockerfile}")

            if not os.path.exists(dockerfile):
                print(f"   ❌ {dockerfile} non trouvé")
                return False

            # Construire l'image
            result = subprocess.run([
                'docker', 'build', '-f', dockerfile, '-t', DOCKER_IMAGE, '.'
            ], capture_output=True, text=True)

            if result.returncode == 0:
                print("   ✅ Image construite avec succès")
                return True
            else:
                print(f"   ❌ Erreur construction: {result.stderr}")
                return False

        except Exception as e:
            print(f"   ❌ Erreur: {e}")
            return False

    async def start_container(self) -> bool:
        """Démarre le container"""
        print("🚀 Démarrage du container...")

        try:
            # Arrêter le container existant s'il existe
            await self.stop_container()

            # Préparer les variables d'environnement
            env_vars = []

            # Variables météo (obligatoires)
            weather_vars = ['OPENWEATHER_API_KEY']
            for var in weather_vars:
                value = os.getenv(var)
                if value:
                    env_vars.extend(['-e', f'{var}={value}'])

            # Variables Azure AD (optionnelles)
            azure_vars = ['AZURE_AD_TENANT_ID',
                          'AZURE_AD_CLIENT_ID', 'AZURE_AD_CLIENT_SECRET']
            for var in azure_vars:
                value = os.getenv(var)
                if value:
                    env_vars.extend(['-e', f'{var}={value}'])

            # Commande Docker
            cmd = [
                'docker', 'run', '-d',
                '--name', self.container_name,
                '-p', f'{DOCKER_PORT}:8000'
            ] + env_vars + [DOCKER_IMAGE]

            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode == 0:
                self.container_id = result.stdout.strip()
                print(f"   ✅ Container démarré: {self.container_id[:12]}")

                # Attendre que le serveur soit prêt
                await asyncio.sleep(3)

                # Vérifier que le container tourne
                if await self.is_container_running():
                    self.is_running = True
                    return True
                else:
                    print("   ❌ Container arrêté après démarrage")
                    await self.show_logs()
                    return False
            else:
                print(f"   ❌ Erreur démarrage: {result.stderr}")
                return False

        except Exception as e:
            print(f"   ❌ Erreur: {e}")
            return False

    async def is_container_running(self) -> bool:
        """Vérifie si le container tourne"""
        try:
            result = subprocess.run([
                'docker', 'ps', '--filter', f'name={self.container_name}', '--format', '{{.Names}}'
            ], capture_output=True, text=True)

            return self.container_name in result.stdout
        except:
            return False

    async def show_logs(self):
        """Affiche les logs du container"""
        try:
            result = subprocess.run([
                'docker', 'logs', self.container_name
            ], capture_output=True, text=True)

            if result.stdout:
                print("📋 Logs du container:")
                # 10 dernières lignes
                for line in result.stdout.split('\n')[-10:]:
                    if line.strip():
                        print(f"   {line}")
        except:
            pass

    async def stop_container(self):
        """Arrête et supprime le container"""
        try:
            # Arrêter
            subprocess.run(['docker', 'stop', self.container_name],
                           capture_output=True, text=True)
            # Supprimer
            subprocess.run(['docker', 'rm', self.container_name],
                           capture_output=True, text=True)
        except:
            pass

        self.is_running = False
        self.container_id = None


class DockerMCPClient:
    """Client pour le serveur MCP dans Docker"""

    def __init__(self, server_url: str):
        self.server_url = server_url.rstrip('/')
        self.session = requests.Session()
        self.message_id = 0

    def get_next_id(self):
        self.message_id += 1
        return self.message_id

    async def test_health(self) -> bool:
        """Teste l'endpoint de santé"""
        try:
            response = self.session.get(
                f"{self.server_url}/health", timeout=10)
            return response.status_code == 200
        except:
            return False

    async def call_mcp_tool(self, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Appelle un outil MCP"""
        try:
            # Message MCP
            message = {
                "jsonrpc": "2.0",
                "id": self.get_next_id(),
                "method": "tools/call",
                "params": {
                    "name": tool_name,
                    "arguments": arguments
                }
            }

            response = self.session.post(
                f"{self.server_url}/mcp",
                json=message,
                timeout=30
            )

            if response.status_code == 200:
                result = response.json()

                # Extraire les données du format MCP
                if "result" in result and "content" in result["result"]:
                    content = result["result"]["content"]
                    if isinstance(content, list) and len(content) > 0:
                        text_content = content[0].get("text", "")
                        if text_content:
                            return json.loads(text_content)

                return {"success": False, "error": "Invalid response format"}
            else:
                return {"success": False, "error": f"HTTP {response.status_code}: {response.text}"}

        except Exception as e:
            return {"success": False, "error": str(e)}

    async def get_weather(self, city: str, unit: str = "celsius") -> Dict[str, Any]:
        """Récupère la météo"""
        return await self.call_mcp_tool("get_weather", {"city": city, "unit": unit})


class DockerTester:
    """Testeur pour le container Docker"""

    def __init__(self):
        self.docker_manager = DockerMCPManager()
        self.mcp_client = DockerMCPClient(LOCAL_URL)

        # Initialiser les clients IA si disponibles
        self.azure_openai_client = None
        self.claude_client = None

        if has_azure_openai:
            self.azure_openai_client = openai.AzureOpenAI(
                api_key=os.getenv('AZURE_OPENAI_API_KEY'),
                api_version=os.getenv(
                    'AZURE_OPENAI_API_VERSION', '2024-05-01-preview'),
                azure_endpoint=os.getenv('AZURE_OPENAI_ENDPOINT')
            )
            self.deployment_name = os.getenv('AZURE_OPENAI_DEPLOYMENT_NAME')
            print(f"✅ Client Azure OpenAI configuré")

        if has_claude:
            self.claude_client = anthropic.Anthropic(
                api_key=os.getenv('ANTHROPIC_API_KEY'))
            print(f"✅ Client Claude configuré")

    async def setup_docker(self) -> bool:
        """Configure et démarre Docker"""
        # Construire l'image
        if not await self.docker_manager.build_image():
            return False

        # Démarrer le container
        if not await self.docker_manager.start_container():
            return False

        # Tester la connectivité
        print("🌐 Test de connectivité...")
        for attempt in range(5):
            if await self.mcp_client.test_health():
                print("   ✅ Serveur Docker accessible")
                return True
            print(f"   ⏳ Tentative {attempt + 1}/5...")
            await asyncio.sleep(2)

        print("   ❌ Serveur Docker inaccessible")
        await self.docker_manager.show_logs()
        return False

    async def test_mcp_weather_direct(self) -> bool:
        """Teste l'appel direct à l'API météo MCP"""
        print("🌤️ Test direct de l'API météo MCP...")

        test_cities = ["Paris", "London", "Tokyo"]
        success_count = 0

        for city in test_cities:
            result = await self.mcp_client.get_weather(city)
            if result.get("success"):
                temp = result["data"]["temperature"]
                unit = result["data"]["unit"]
                condition = result["data"]["condition"]
                print(f"   ✅ {city}: {temp}{unit}, {condition}")
                success_count += 1
            else:
                print(f"   ❌ {city}: {result.get('error', 'Unknown error')}")

        print(f"   📊 Succès: {success_count}/{len(test_cities)}")
        return success_count > 0

    async def test_with_azure_openai(self) -> bool:
        """Teste l'intégration avec Azure OpenAI"""
        if not self.azure_openai_client:
            print("⚠️ Azure OpenAI non configuré - test ignoré")
            return True

        print("🤖 Test avec Azure OpenAI...")

        try:
            # Récupérer des données météo
            weather_result = await self.mcp_client.get_weather("Paris")
            if not weather_result.get("success"):
                print(
                    f"   ❌ Impossible de récupérer la météo: {weather_result.get('error')}")
                return False

            # Construire le contexte
            weather_data = weather_result["data"]
            context = f"Météo à Paris: {weather_data['temperature']}{weather_data['unit']}, {weather_data['condition']}"

            # Appeler Azure OpenAI
            response = self.azure_openai_client.chat.completions.create(
                model=self.deployment_name,
                messages=[
                    {"role": "user", "content": f"{context}\n\nDonne-moi un conseil vestimentaire pour aujourd'hui à Paris."}
                ],
                max_tokens=200
            )

            answer = response.choices[0].message.content
            print(f"   ✅ Réponse Azure OpenAI: {answer[:100]}...")
            return True

        except Exception as e:
            print(f"   ❌ Erreur Azure OpenAI: {e}")
            return False

    async def test_with_claude(self) -> bool:
        """Teste l'intégration avec Claude"""
        if not self.claude_client:
            print("⚠️ Claude non configuré - test ignoré")
            return True

        print("🧠 Test avec Claude...")

        try:
            # Récupérer des données météo
            weather_result = await self.mcp_client.get_weather("London")
            if not weather_result.get("success"):
                print(
                    f"   ❌ Impossible de récupérer la météo: {weather_result.get('error')}")
                return False

            # Construire le contexte
            weather_data = weather_result["data"]
            context = f"Météo à Londres: {weather_data['temperature']}{weather_data['unit']}, {weather_data['condition']}"

            # Appeler Claude
            response = self.claude_client.messages.create(
                model="claude-3-7-sonnet-20250219",
                max_tokens=200,
                messages=[
                    {"role": "user", "content": f"{context}\n\nQue recommandes-tu comme activité pour aujourd'hui à Londres ?"}
                ]
            )

            answer = response.content[0].text
            print(f"   ✅ Réponse Claude: {answer[:100]}...")
            return True

        except Exception as e:
            print(f"   ❌ Erreur Claude: {e}")
            return False

    async def cleanup(self):
        """Nettoie les ressources"""
        print("🧹 Nettoyage...")
        await self.docker_manager.stop_container()
        print("   ✅ Container arrêté")


async def run_docker_tests():
    """Exécute tous les tests Docker"""

    tester = DockerTester()

    print(f"\n🎯 TESTS DOCKER LOCAL")
    print("=" * 40)

    results = {}

    try:
        # Test 1: Setup Docker
        results['docker_setup'] = await tester.setup_docker()

        # Test 2: API MCP directe
        if results['docker_setup']:
            results['mcp_direct'] = await tester.test_mcp_weather_direct()
        else:
            results['mcp_direct'] = False

        # Test 3: Intégration Azure OpenAI
        if results['mcp_direct']:
            results['azure_openai'] = await tester.test_with_azure_openai()
        else:
            results['azure_openai'] = False

        # Test 4: Intégration Claude
        if results['mcp_direct']:
            results['claude'] = await tester.test_with_claude()
        else:
            results['claude'] = False

        # Résumé
        print(f"\n🎉 RÉSUMÉ DES TESTS DOCKER")
        print("=" * 35)

        for test_name, success in results.items():
            status = "✅ RÉUSSI" if success else "❌ ÉCHEC"
            test_display = {
                'docker_setup': 'Setup Docker',
                'mcp_direct': 'API MCP directe',
                'azure_openai': 'Intégration Azure OpenAI',
                'claude': 'Intégration Claude'
            }
            print(f"   {test_display[test_name]}: {status}")

        success_count = sum(results.values())
        total_tests = len(results)

        print(f"\n📊 Score global: {success_count}/{total_tests}")

        if success_count == total_tests:
            print("🎉 Tous les tests Docker sont réussis !")
        elif success_count >= total_tests - 1:
            print("✅ Container Docker majoritairement fonctionnel")
        else:
            print("⚠️ Problèmes détectés dans le container Docker")

    finally:
        await tester.cleanup()

    return results


if __name__ == "__main__":
    print(f"🔧 Image Docker: {DOCKER_IMAGE}")
    print(f"🌐 URL locale: {LOCAL_URL}")
    print(
        f"🤖 Azure OpenAI: {'✅ Configuré' if has_azure_openai else '❌ Manquant'}")
    print(f"🧠 Claude: {'✅ Configuré' if has_claude else '❌ Manquant'}")

    try:
        asyncio.run(run_docker_tests())
    except KeyboardInterrupt:
        print("\n⚠️ Test interrompu par l'utilisateur")
    except Exception as e:
        print(f"\n❌ Erreur générale: {e}")
        import traceback
        traceback.print_exc()
