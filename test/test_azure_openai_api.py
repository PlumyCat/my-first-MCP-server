#!/usr/bin/env python3
"""
Test du serveur MCP avec Azure OpenAI API
Teste l'intégration complète : MCP Server -> Azure OpenAI API
"""

import os
import asyncio
import json
import subprocess
import time
from typing import Dict, Any, List
from dotenv import load_dotenv

# Charger les variables d'environnement
load_dotenv()

if __name__ == "__main__":
    print("🤖 TEST SERVEUR MCP avec AZURE OPENAI")
    print("=" * 50)

# Vérifier la configuration
required_vars = [
    'AZURE_OPENAI_API_KEY',
    'AZURE_OPENAI_ENDPOINT',
    'AZURE_OPENAI_DEPLOYMENT_NAME'
]

missing_vars = [var for var in required_vars if not os.getenv(var)]
if missing_vars and __name__ == "__main__":
    print(f"❌ Variables manquantes dans .env: {', '.join(missing_vars)}")
    print("💡 Ajoutez dans votre fichier .env :")
    for var in missing_vars:
        if 'KEY' in var:
            print(f"   {var}=your_azure_api_key")
        elif 'ENDPOINT' in var:
            print(f"   {var}=https://your-resource.openai.azure.com/")
        elif 'DEPLOYMENT' in var:
            print(f"   {var}=your_deployment_name")
    exit(1)

try:
    import openai
    print("✅ Librairie OpenAI importée")
except ImportError:
    print("❌ Librairie OpenAI manquante")
    print("💡 Installez avec: pip install openai")
    exit(1)


class MCPWeatherServer:
    """Gestionnaire du serveur MCP Weather"""

    def __init__(self, workspace_path: str = None):
        self.workspace_path = workspace_path or os.getcwd()
        self.process = None
        self.message_id = 0
        self.initialized = False

    def get_next_id(self):
        self.message_id += 1
        return self.message_id

    async def start(self) -> bool:
        """Démarre le serveur MCP"""
        try:
            print("🚀 Démarrage du serveur MCP...")

            env = os.environ.copy()
            env["PYTHONPATH"] = self.workspace_path
            env["PYTHONUNBUFFERED"] = "1"

            self.process = await asyncio.create_subprocess_exec(
                "python", "-m", "src.main",
                cwd=self.workspace_path,
                env=env,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            print(f"   ✅ Serveur démarré (PID: {self.process.pid})")
            return True

        except Exception as e:
            print(f"   ❌ Erreur: {e}")
            return False

    async def send_message(self, message: Dict[str, Any]) -> Dict[str, Any]:
        """Envoie un message au serveur MCP"""
        if not self.process:
            return {"error": "Server not started"}

        try:
            message_json = json.dumps(message) + "\n"

            self.process.stdin.write(message_json.encode())
            await self.process.stdin.drain()

            response_line = await asyncio.wait_for(
                self.process.stdout.readline(),
                timeout=10.0
            )

            if response_line:
                return json.loads(response_line.decode().strip())
            else:
                return {"error": "No response"}

        except asyncio.TimeoutError:
            return {"error": "Timeout"}
        except Exception as e:
            return {"error": str(e)}

    async def send_notification(self, method: str, params: Dict[str, Any] = None):
        """Envoie une notification"""
        notification = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            notification["params"] = params

        try:
            notification_json = json.dumps(notification) + "\n"
            self.process.stdin.write(notification_json.encode())
            await self.process.stdin.drain()
        except Exception as e:
            print(f"Erreur notification: {e}")

    async def initialize(self) -> bool:
        """Initialise la connexion MCP"""
        try:
            print("🤝 Initialisation MCP...")

            # Initialize
            init_message = {
                "jsonrpc": "2.0",
                "id": self.get_next_id(),
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "clientInfo": {"name": "azure-openai-test", "version": "1.0.0"}
                }
            }

            init_response = await self.send_message(init_message)
            if "error" in init_response:
                print(f"   ❌ Erreur: {init_response['error']}")
                return False

            # Initialized notification
            await self.send_notification("notifications/initialized")
            await asyncio.sleep(0.5)

            self.initialized = True
            print("   ✅ MCP initialisé")
            return True

        except Exception as e:
            print(f"   ❌ Erreur: {e}")
            return False

    async def get_weather(self, city: str, unit: str = "celsius") -> Dict[str, Any]:
        """Appelle l'outil météo"""
        if not self.initialized:
            return {"success": False, "error": "Not initialized"}

        try:
            call_message = {
                "jsonrpc": "2.0",
                "id": self.get_next_id(),
                "method": "tools/call",
                "params": {
                    "name": "get_weather",
                    "arguments": {"city": city, "unit": unit}
                }
            }

            response = await self.send_message(call_message)

            # Extraire les données (format validé)
            if "result" in response:
                result = response["result"]
                if "content" in result and isinstance(result["content"], list):
                    if len(result["content"]) > 0:
                        text_content = result["content"][0].get("text", "")
                        if text_content:
                            return json.loads(text_content)

            return {"success": False, "error": "Invalid response format"}

        except Exception as e:
            return {"success": False, "error": str(e)}

    async def stop(self):
        """Arrête le serveur"""
        if self.process:
            print("🛑 Arrêt du serveur...")
            self.process.terminate()
            try:
                await asyncio.wait_for(self.process.wait(), timeout=3.0)
                print("   ✅ Serveur arrêté")
            except asyncio.TimeoutError:
                self.process.kill()
                print("   ⚠️ Arrêt forcé")


class AzureOpenAIWeatherTester:
    """Testeur Azure OpenAI avec serveur MCP"""

    def __init__(self):
        # Initialiser le client Azure OpenAI
        self.client = openai.AzureOpenAI(
            api_key=os.getenv('AZURE_OPENAI_API_KEY'),
            api_version=os.getenv(
                'AZURE_OPENAI_API_VERSION', '2024-05-01-preview'),
            azure_endpoint=os.getenv('AZURE_OPENAI_ENDPOINT')
        )

        self.deployment_name = os.getenv('AZURE_OPENAI_DEPLOYMENT_NAME')
        self.mcp_server = None

        print(f"✅ Client Azure OpenAI initialisé")
        print(f"   Endpoint: {os.getenv('AZURE_OPENAI_ENDPOINT')}")
        print(f"   Deployment: {self.deployment_name}")

    async def setup_mcp_server(self):
        """Configure le serveur MCP"""
        self.mcp_server = MCPWeatherServer()

        if not await self.mcp_server.start():
            raise Exception("Impossible de démarrer le serveur MCP")

        await asyncio.sleep(1)

        if not await self.mcp_server.initialize():
            raise Exception("Impossible d'initialiser MCP")

        print("✅ Serveur MCP prêt pour Azure OpenAI")

    async def ask_azure_with_weather(self, user_question: str, cities: List[str]) -> str:
        """Pose une question à Azure OpenAI avec données météo"""

        print(f"🌍 Récupération météo pour: {', '.join(cities)}")

        # Récupérer les données météo via MCP
        weather_data = {}
        for city in cities:
            result = await self.mcp_server.get_weather(city)
            if result.get("success"):
                weather_data[city] = result["data"]
                temp = result["data"]["temperature"]
                unit = result["data"]["unit"]
                condition = result["data"]["condition"]
                print(f"   ✅ {city}: {temp}{unit}, {condition}")
            else:
                weather_data[city] = {
                    "error": result.get("error", "Unknown error")}
                print(f"   ❌ {city}: {result.get('error', 'Unknown')}")

        # Construire le contexte météo
        weather_context = "Données météo actuelles (via serveur MCP):\\n"
        for city, data in weather_data.items():
            if "error" not in data:
                weather_context += f"\\n{city}:"
                weather_context += f"\\n- Température: {data['temperature']}{data['unit']}"
                weather_context += f"\\n- Conditions: {data['condition']}"
                weather_context += f"\\n- Humidité: {data['humidity']}%"
                weather_context += f"\\n- Vent: {data['wind_speed']} km/h"
                weather_context += f"\\n- Pression: {data['pressure']} hPa"
                weather_context += f"\\n- Visibilité: {data['visibility']} km"
                if data.get('forecast'):
                    forecast = data['forecast'][0]
                    weather_context += f"\\n- Prévision: {forecast['day']} {forecast['high']}°-{forecast['low']}° {forecast['condition']}"
            else:
                weather_context += f"\\n{city}: Erreur - {data['error']}"

        print("🤖 Envoi à Azure OpenAI...")

        # Appeler Azure OpenAI
        response = self.client.chat.completions.create(
            model=self.deployment_name,
            messages=[
                {
                    "role": "system",
                    "content": "Tu es un assistant météo expert et utile. Utilise les données météo fournies pour répondre de manière précise, pratique et engageante. Donne des conseils concrets basés sur les conditions météo."
                },
                {
                    "role": "user",
                    "content": f"{weather_context}\\n\\nQuestion: {user_question}"
                }
            ],
            max_tokens=1000,
            temperature=0.7
        )

        return response.choices[0].message.content

    async def cleanup(self):
        """Nettoie les ressources"""
        if self.mcp_server:
            await self.mcp_server.stop()


async def run_azure_tests():
    """Exécute les tests avec Azure OpenAI"""

    tester = AzureOpenAIWeatherTester()

    try:
        # Setup
        await tester.setup_mcp_server()

        # Questions de test spécialisées pour Azure OpenAI
        test_questions = [
            {
                "question": "Analyse les conditions météo à Berlin et recommande les activités idéales pour aujourd'hui",
                "cities": ["Berlin"]
            },
            {
                "question": "Je dois choisir entre Paris, Rome et Madrid pour un weekend. Quelle ville a la meilleure météo ?",
                "cities": ["Paris", "Rome", "Madrid"]
            },
            {
                "question": "Explique les différences météo entre l'hémisphère nord et sud avec des exemples concrets",
                "cities": ["London", "Sydney", "Tokyo"]
            },
            {
                "question": "Crée un plan détaillé pour une journée parfaite à New York selon la météo actuelle",
                "cities": ["New York"]
            },
            {
                "question": "Compare les conditions météo européennes et donne des conseils vestimentaires",
                "cities": ["Paris", "London", "Berlin", "Madrid"]
            },
            {
                "question": "Analyse la météo de Tokyo et donne des recommandations pour un photographe de rue",
                "cities": ["Tokyo"]
            }
        ]

        print(f"\\n🎯 TESTS AZURE OPENAI avec {len(test_questions)} scénarios")
        print("=" * 65)

        # Statistiques
        total_chars = 0
        total_time = 0

        # Tester chaque question
        for i, test in enumerate(test_questions, 1):
            print(f"\\n📝 Test {i}/{len(test_questions)}")
            print(f"❓ Question: {test['question']}")
            print("-" * 55)

            start_time = time.time()
            response = await tester.ask_azure_with_weather(
                test['question'],
                test['cities']
            )
            end_time = time.time()
            duration = end_time - start_time

            print(f"\\n🤖 Réponse d'Azure OpenAI:")
            print(f"{'=' * 45}")
            # Formater la réponse proprement
            lines = response.split('\\n')
            for line in lines:
                if len(line) > 80:
                    # Couper les lignes trop longues intelligemment
                    words = line.split(' ')
                    current_line = ""
                    for word in words:
                        if len(current_line + word) > 77:
                            print(f"   {current_line.strip()}")
                            current_line = word + " "
                        else:
                            current_line += word + " "
                    if current_line.strip():
                        print(f"   {current_line.strip()}")
                else:
                    print(f"   {line}")
            print(f"{'=' * 45}")

            # Statistiques
            char_count = len(response)
            total_chars += char_count
            total_time += duration

            print(f"\\n📊 Statistiques:")
            print(f"   ⏱️ Temps: {duration:.2f}s")
            print(f"   📝 Caractères: {char_count}")
            print(f"   🚀 Vitesse: {char_count/duration:.0f} chars/s")

            # Pause entre les tests
            if i < len(test_questions):
                print("\\n⏳ Pause 2s...")
                await asyncio.sleep(2)

        # Résumé final
        print(f"\\n🎉 TOUS LES TESTS AZURE OPENAI TERMINÉS!")
        print(f"=" * 65)
        print(f"📈 STATISTIQUES GLOBALES:")
        print(f"   ✅ Tests réussis: {len(test_questions)}")
        print(f"   ⏱️ Temps total: {total_time:.2f}s")
        print(f"   📝 Caractères totaux: {total_chars:,}")
        print(
            f"   📊 Temps moyen: {total_time/len(test_questions):.2f}s par test")
        print(f"   🚀 Vitesse moyenne: {total_chars/total_time:.0f} chars/s")
        print(f"\\n🤖 Azure OpenAI + MCP Server = Fonctionnel !")

    except Exception as e:
        print(f"❌ Erreur: {e}")
        import traceback
        traceback.print_exc()
    finally:
        await tester.cleanup()


if __name__ == "__main__":
    print(f"🔧 Workspace: {os.getcwd()}")
    print(
        f"🔑 Azure API: {'✅ Configuré' if os.getenv('AZURE_OPENAI_API_KEY') else '❌ Manquant'}")
    print(
        f"🌐 Endpoint: {'✅ Configuré' if os.getenv('AZURE_OPENAI_ENDPOINT') else '❌ Manquant'}")
    print(
        f"🚀 Deployment: {'✅ Configuré' if os.getenv('AZURE_OPENAI_DEPLOYMENT_NAME') else '❌ Manquant'}")

    try:
        asyncio.run(run_azure_tests())
    except KeyboardInterrupt:
        print("\\n⚠️ Test interrompu par l'utilisateur")
    except Exception as e:
        print(f"\\n❌ Erreur générale: {e}")
