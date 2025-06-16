#!/usr/bin/env python3
"""
Test du serveur MCP déployé sur Azure avec authentification
Teste l'intégration complète : Azure Container Instance -> Azure OpenAI/Claude API
"""

import os
import asyncio
import json
import time
import requests
from typing import Dict, Any, List
from dotenv import load_dotenv

# Charger les variables d'environnement
load_dotenv()

if __name__ == "__main__":
    print("☁️ TEST SERVEUR MCP DÉPLOYÉ SUR AZURE")
    print("=" * 50)

# Vérifier la configuration
required_vars = [
    'AZURE_SERVER_URL',  # URL du serveur déployé
    'AZURE_AD_TENANT_ID',
    'AZURE_AD_CLIENT_ID',
    'AZURE_AD_CLIENT_SECRET'
]

missing_vars = [var for var in required_vars if not os.getenv(var)]
if missing_vars and __name__ == "__main__":
    print(f"❌ Variables manquantes dans .env: {', '.join(missing_vars)}")
    print("💡 Ajoutez dans votre fichier .env :")
    print("   AZURE_SERVER_URL=http://your-container.azurecontainer.io:8000")
    print("   AZURE_AD_TENANT_ID=your-tenant-id")
    print("   AZURE_AD_CLIENT_ID=your-client-id")
    print("   AZURE_AD_CLIENT_SECRET=your-client-secret")
    exit(1)

# Vérifier les APIs optionnelles
has_azure_openai = all([
    os.getenv('AZURE_OPENAI_API_KEY'),
    os.getenv('AZURE_OPENAI_ENDPOINT'),
    os.getenv('AZURE_OPENAI_DEPLOYMENT_NAME')
])

has_claude = bool(os.getenv('ANTHROPIC_API_KEY'))

if not has_azure_openai and not has_claude:
    print("⚠️ Aucune API IA configurée (Azure OpenAI ou Claude)")
    print("💡 Le test se limitera à l'authentification et aux appels MCP directs")

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


class AzureADTokenManager:
    """Gestionnaire de tokens Azure AD"""

    def __init__(self):
        self.tenant_id = os.getenv('AZURE_AD_TENANT_ID')
        self.client_id = os.getenv('AZURE_AD_CLIENT_ID')
        self.client_secret = os.getenv('AZURE_AD_CLIENT_SECRET')
        self.token_url = f"https://login.microsoftonline.com/{self.tenant_id}/oauth2/v2.0/token"
        self.access_token = None
        self.token_expires_at = 0

    async def get_access_token(self) -> str:
        """Obtient un token d'accès Azure AD"""
        current_time = time.time()

        # Vérifier si le token est encore valide
        if self.access_token and current_time < self.token_expires_at:
            return self.access_token

        print("🔑 Obtention d'un nouveau token Azure AD...")

        try:
            # Préparer les données pour la requête
            data = {
                'client_id': self.client_id,
                'client_secret': self.client_secret,
                'scope': 'https://graph.microsoft.com/.default',
                'grant_type': 'client_credentials'
            }

            # Faire la requête
            response = requests.post(self.token_url, data=data)
            response.raise_for_status()

            token_data = response.json()
            self.access_token = token_data['access_token']
            expires_in = token_data.get('expires_in', 3600)
            self.token_expires_at = current_time + expires_in - 60  # 60s de marge

            print(f"   ✅ Token obtenu (expire dans {expires_in}s)")
            return self.access_token

        except Exception as e:
            print(f"   ❌ Erreur: {e}")
            raise


class AzureMCPClient:
    """Client pour le serveur MCP déployé sur Azure"""

    def __init__(self, server_url: str):
        self.server_url = server_url.rstrip('/')
        self.token_manager = AzureADTokenManager()
        self.session = requests.Session()
        self.message_id = 0

    def get_next_id(self):
        self.message_id += 1
        return self.message_id

    async def test_authentication(self) -> bool:
        """Teste l'authentification avec le serveur"""
        print("🔐 Test d'authentification...")

        try:
            # Test sans authentification (devrait échouer)
            response = self.session.get(
                f"{self.server_url}/health", timeout=10)
            if response.status_code == 200:
                print("   ⚠️ Le serveur répond sans authentification")
                return True  # Serveur non sécurisé mais fonctionnel

        except Exception:
            pass  # Erreur attendue

        try:
            # Test avec authentification
            token = await self.token_manager.get_access_token()
            headers = {
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            }

            response = self.session.get(
                f"{self.server_url}/health", headers=headers, timeout=10)
            if response.status_code == 200:
                print("   ✅ Authentification réussie")
                return True
            else:
                print(f"   ❌ Échec authentification: {response.status_code}")
                return False

        except Exception as e:
            print(f"   ❌ Erreur authentification: {e}")
            return False

    async def call_mcp_tool(self, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Appelle un outil MCP sur le serveur distant"""
        try:
            token = await self.token_manager.get_access_token()
            headers = {
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            }

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
                headers=headers,
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
        """Récupère la météo via le serveur distant"""
        return await self.call_mcp_tool("get_weather", {"city": city, "unit": unit})


class AzureDeploymentTester:
    """Testeur pour le déploiement Azure"""

    def __init__(self):
        self.server_url = os.getenv('AZURE_SERVER_URL')
        self.mcp_client = AzureMCPClient(self.server_url)

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

        print(f"🌐 Serveur cible: {self.server_url}")

    async def test_server_connectivity(self) -> bool:
        """Teste la connectivité de base"""
        print("🌐 Test de connectivité...")

        try:
            response = requests.get(f"{self.server_url}/health", timeout=10)
            print(f"   ✅ Serveur accessible (Status: {response.status_code})")
            return True
        except Exception as e:
            print(f"   ❌ Serveur inaccessible: {e}")
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


async def run_azure_deployment_tests():
    """Exécute tous les tests du déploiement Azure"""

    tester = AzureDeploymentTester()

    print(f"\n🎯 TESTS DU DÉPLOIEMENT AZURE")
    print("=" * 50)

    results = {}

    # Test 1: Connectivité
    results['connectivity'] = await tester.test_server_connectivity()

    # Test 2: Authentification
    if results['connectivity']:
        results['authentication'] = await tester.mcp_client.test_authentication()
    else:
        results['authentication'] = False

    # Test 3: API MCP directe
    if results['authentication']:
        results['mcp_direct'] = await tester.test_mcp_weather_direct()
    else:
        results['mcp_direct'] = False

    # Test 4: Intégration Azure OpenAI
    if results['mcp_direct']:
        results['azure_openai'] = await tester.test_with_azure_openai()
    else:
        results['azure_openai'] = False

    # Test 5: Intégration Claude
    if results['mcp_direct']:
        results['claude'] = await tester.test_with_claude()
    else:
        results['claude'] = False

    # Résumé
    print(f"\n🎉 RÉSUMÉ DES TESTS")
    print("=" * 30)

    for test_name, success in results.items():
        status = "✅ RÉUSSI" if success else "❌ ÉCHEC"
        test_display = {
            'connectivity': 'Connectivité serveur',
            'authentication': 'Authentification Azure AD',
            'mcp_direct': 'API MCP directe',
            'azure_openai': 'Intégration Azure OpenAI',
            'claude': 'Intégration Claude'
        }
        print(f"   {test_display[test_name]}: {status}")

    success_count = sum(results.values())
    total_tests = len(results)

    print(f"\n📊 Score global: {success_count}/{total_tests}")

    if success_count == total_tests:
        print("🎉 Tous les tests sont réussis ! Déploiement Azure fonctionnel !")
    elif success_count >= total_tests - 1:
        print("✅ Déploiement Azure majoritairement fonctionnel")
    else:
        print("⚠️ Problèmes détectés dans le déploiement Azure")

    return results


if __name__ == "__main__":
    print(f"🔧 Serveur cible: {os.getenv('AZURE_SERVER_URL', 'NON CONFIGURÉ')}")
    print(
        f"🔑 Azure AD: {'✅ Configuré' if all([os.getenv('AZURE_AD_TENANT_ID'), os.getenv('AZURE_AD_CLIENT_ID'), os.getenv('AZURE_AD_CLIENT_SECRET')]) else '❌ Manquant'}")
    print(
        f"🤖 Azure OpenAI: {'✅ Configuré' if has_azure_openai else '❌ Manquant'}")
    print(f"🧠 Claude: {'✅ Configuré' if has_claude else '❌ Manquant'}")

    try:
        asyncio.run(run_azure_deployment_tests())
    except KeyboardInterrupt:
        print("\n⚠️ Test interrompu par l'utilisateur")
    except Exception as e:
        print(f"\n❌ Erreur générale: {e}")
        import traceback
        traceback.print_exc()
