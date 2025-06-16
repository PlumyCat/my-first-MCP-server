#!/usr/bin/env python3
"""
Test du serveur MCP avec Claude API
Teste l'intégration complète : MCP Server -> Claude API
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

print("🧠 TEST SERVEUR MCP avec CLAUDE API")
print("=" * 50)

# Vérifier la configuration
if not os.getenv('ANTHROPIC_API_KEY'):
    print("❌ ANTHROPIC_API_KEY non trouvée dans .env")
    print("💡 Ajoutez votre clé Claude dans le fichier .env :")
    print("   ANTHROPIC_API_KEY=sk-ant-api03-...")
    exit(1)

try:
    import anthropic
    print("✅ Librairie Anthropic importée")
except ImportError:
    print("❌ Librairie Anthropic manquante")
    print("💡 Installez avec: pip install anthropic")
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
                    "clientInfo": {"name": "claude-api-test", "version": "1.0.0"}
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


class ClaudeWeatherTester:
    """Testeur Claude avec serveur MCP"""
    
    def __init__(self):
        self.client = anthropic.Anthropic(api_key=os.getenv('ANTHROPIC_API_KEY'))
        self.mcp_server = None
        print("✅ Client Claude initialisé")
    
    async def setup_mcp_server(self):
        """Configure le serveur MCP"""
        self.mcp_server = MCPWeatherServer()
        
        if not await self.mcp_server.start():
            raise Exception("Impossible de démarrer le serveur MCP")
        
        await asyncio.sleep(1)
        
        if not await self.mcp_server.initialize():
            raise Exception("Impossible d'initialiser MCP")
        
        print("✅ Serveur MCP prêt pour Claude")
    
    async def ask_claude_with_weather(self, user_question: str, cities: List[str]) -> str:
        """Pose une question à Claude avec données météo en temps réel"""
        
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
                weather_data[city] = {"error": result.get("error", "Unknown error")}
                print(f"   ❌ {city}: {result.get('error', 'Unknown')}")
        
        # Construire le prompt pour Claude
        weather_context = "Données météo actuelles (via serveur MCP):\\n"
        for city, data in weather_data.items():
            if "error" not in data:
                weather_context += f"\\n{city}:"
                weather_context += f"\\n- Température: {data['temperature']}{data['unit']}"
                weather_context += f"\\n- Conditions: {data['condition']}"
                weather_context += f"\\n- Humidité: {data['humidity']}%"
                weather_context += f"\\n- Vent: {data['wind_speed']} km/h"
                weather_context += f"\\n- Pression: {data['pressure']} hPa"
                if data.get('forecast'):
                    forecast = data['forecast'][0]
                    weather_context += f"\\n- Prévision: {forecast['day']} {forecast['high']}°-{forecast['low']}° {forecast['condition']}"
            else:
                weather_context += f"\\n{city}: Erreur - {data['error']}"
        
        print("🧠 Envoi à Claude...")
        
        # Appeler Claude
        response = self.client.messages.create(
            model="claude-3-7-sonnet-20250219",
            max_tokens=1000,
            messages=[
                {
                    "role": "user",
                    "content": f"{weather_context}\\n\\nQuestion: {user_question}"
                }
            ]
        )
        
        return response.content[0].text
    
    async def cleanup(self):
        """Nettoie les ressources"""
        if self.mcp_server:
            await self.mcp_server.stop()


async def run_claude_tests():
    """Exécute les tests avec Claude"""
    
    tester = ClaudeWeatherTester()
    
    try:
        # Setup
        await tester.setup_mcp_server()
        
        # Questions de test
        test_questions = [
            {
                "question": "Quelle ville a la meilleure météo aujourd'hui pour se promener ?",
                "cities": ["Paris", "London", "Madrid"]
            },
            {
                "question": "Dois-je prendre un parapluie et une veste si je vais à New York aujourd'hui ?",
                "cities": ["New York"]
            },
            {
                "question": "Compare la météo entre Tokyo et Sydney et explique les différences",
                "cities": ["Tokyo", "Sydney"]
            },
            {
                "question": "Planifie ma journée idéale à Berlin en fonction de la météo actuelle",
                "cities": ["Berlin"]
            },
            {
                "question": "Quelle ville européenne choisir pour un pique-nique ce weekend ?",
                "cities": ["Paris", "Rome", "Madrid", "Berlin"]
            }
        ]
        
        print(f"\\n🎯 TESTS CLAUDE avec {len(test_questions)} scénarios")
        print("=" * 60)
        
        # Tester chaque question
        for i, test in enumerate(test_questions, 1):
            print(f"\\n📝 Test {i}/{len(test_questions)}")
            print(f"❓ Question: {test['question']}")
            print("-" * 50)
            
            start_time = time.time()
            response = await tester.ask_claude_with_weather(
                test['question'], 
                test['cities']
            )
            end_time = time.time()
            
            print(f"\\n🧠 Réponse de Claude:")
            print(f"{'=' * 40}")
            # Formater la réponse sur plusieurs lignes si nécessaire
            lines = response.split('\\n')
            for line in lines:
                if len(line) > 80:
                    # Couper les lignes trop longues
                    words = line.split(' ')
                    current_line = ""
                    for word in words:
                        if len(current_line + word) > 77:
                            print(f"   {current_line}")
                            current_line = word + " "
                        else:
                            current_line += word + " "
                    if current_line.strip():
                        print(f"   {current_line}")
                else:
                    print(f"   {line}")
            print(f"{'=' * 40}")
            
            print(f"\\n⏱️ Temps total: {end_time - start_time:.2f}s")
            print(f"📊 Longueur réponse: {len(response)} caractères")
            
            # Pause entre les tests
            if i < len(test_questions):
                print("\\n⏳ Pause 2s...")
                await asyncio.sleep(2)
        
        print(f"\\n🎉 TOUS LES TESTS CLAUDE TERMINÉS!")
        print(f"✅ {len(test_questions)} scénarios testés avec succès")
        print(f"🧠 Claude + MCP Server = Fonctionnel !")
        
    except Exception as e:
        print(f"❌ Erreur: {e}")
        import traceback
        traceback.print_exc()
    finally:
        await tester.cleanup()


if __name__ == "__main__":
    print(f"🔧 Workspace: {os.getcwd()}")
    print(f"🔑 Claude API: {'✅ Configuré' if os.getenv('ANTHROPIC_API_KEY') else '❌ Manquant'}")
    
    try:
        asyncio.run(run_claude_tests())
    except KeyboardInterrupt:
        print("\\n⚠️ Test interrompu par l'utilisateur")
    except Exception as e:
        print(f"\\n❌ Erreur générale: {e}")