#!/usr/bin/env python3
"""
Comparaison entre Claude et Azure OpenAI avec le serveur MCP
Teste les deux APIs côte à côte avec les mêmes données météo
"""

import os
import asyncio
import json
import subprocess
import time
from typing import Dict, Any, List, Optional
from dotenv import load_dotenv

# Charger les variables d'environnement
load_dotenv()

print("⚡ COMPARAISON CLAUDE vs AZURE OPENAI")
print("=" * 60)

# Vérifier les configurations
claude_available = bool(os.getenv('ANTHROPIC_API_KEY'))
azure_available = all(os.getenv(var) for var in [
    'AZURE_OPENAI_API_KEY', 'AZURE_OPENAI_ENDPOINT', 'AZURE_OPENAI_DEPLOYMENT_NAME'
])

print(f"🧠 Claude API: {'✅ Disponible' if claude_available else '❌ Non configuré'}")
print(f"🤖 Azure OpenAI: {'✅ Disponible' if azure_available else '❌ Non configuré'}")

if not claude_available and not azure_available:
    print("❌ Aucune API configurée - configurez au moins une API dans .env")
    exit(1)

# Imports conditionnels
try:
    import anthropic
    ANTHROPIC_LIB = True
except ImportError:
    ANTHROPIC_LIB = False
    if claude_available:
        print("⚠️ pip install anthropic requis pour Claude")

try:
    import openai
    OPENAI_LIB = True
except ImportError:
    OPENAI_LIB = False
    if azure_available:
        print("⚠️ pip install openai requis pour Azure OpenAI")


class MCPWeatherServer:
    """Gestionnaire du serveur MCP Weather réutilisable"""
    
    def __init__(self, workspace_path: str = None):
        self.workspace_path = workspace_path or os.getcwd()
        self.process = None
        self.message_id = 0
        self.initialized = False
        
    def get_next_id(self):
        self.message_id += 1
        return self.message_id
    
    async def start(self) -> bool:
        try:
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
            return True
        except Exception:
            return False
    
    async def send_message(self, message: Dict[str, Any]) -> Dict[str, Any]:
        if not self.process:
            return {"error": "Server not started"}
        
        try:
            message_json = json.dumps(message) + "\\n"
            self.process.stdin.write(message_json.encode())
            await self.process.stdin.drain()
            
            response_line = await asyncio.wait_for(
                self.process.stdout.readline(), timeout=10.0
            )
            
            if response_line:
                return json.loads(response_line.decode().strip())
            else:
                return {"error": "No response"}
        except Exception as e:
            return {"error": str(e)}
    
    async def send_notification(self, method: str, params: Dict[str, Any] = None):
        notification = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            notification["params"] = params
        
        try:
            notification_json = json.dumps(notification) + "\\n"
            self.process.stdin.write(notification_json.encode())
            await self.process.stdin.drain()
        except Exception:
            pass
    
    async def initialize(self) -> bool:
        try:
            init_message = {
                "jsonrpc": "2.0",
                "id": self.get_next_id(),
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "clientInfo": {"name": "comparison-test", "version": "1.0.0"}
                }
            }
            
            init_response = await self.send_message(init_message)
            if "error" in init_response:
                return False
            
            await self.send_notification("notifications/initialized")
            await asyncio.sleep(0.5)
            
            self.initialized = True
            return True
        except Exception:
            return False
    
    async def get_weather(self, city: str, unit: str = "celsius") -> Dict[str, Any]:
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
        if self.process:
            self.process.terminate()
            try:
                await asyncio.wait_for(self.process.wait(), timeout=3.0)
            except asyncio.TimeoutError:
                self.process.kill()


class AIComparator:
    """Comparateur entre Claude et Azure OpenAI"""
    
    def __init__(self):
        self.mcp_server = None
        self.claude_client = None
        self.azure_client = None
        self.azure_deployment = None
        
        # Initialiser les clients disponibles
        if claude_available and ANTHROPIC_LIB:
            self.claude_client = anthropic.Anthropic(api_key=os.getenv('ANTHROPIC_API_KEY'))
            print("✅ Client Claude initialisé")
        
        if azure_available and OPENAI_LIB:
            self.azure_client = openai.AzureOpenAI(
                api_key=os.getenv('AZURE_OPENAI_API_KEY'),
                api_version=os.getenv('AZURE_OPENAI_API_VERSION', '2024-05-01-preview'),
                azure_endpoint=os.getenv('AZURE_OPENAI_ENDPOINT')
            )
            self.azure_deployment = os.getenv('AZURE_OPENAI_DEPLOYMENT_NAME')
            print("✅ Client Azure OpenAI initialisé")
    
    async def setup_mcp_server(self):
        """Configure le serveur MCP partagé"""
        print("🚀 Démarrage du serveur MCP...")
        self.mcp_server = MCPWeatherServer()
        
        if not await self.mcp_server.start():
            raise Exception("Impossible de démarrer le serveur MCP")
        
        await asyncio.sleep(1)
        
        if not await self.mcp_server.initialize():
            raise Exception("Impossible d'initialiser MCP")
        
        print("✅ Serveur MCP prêt pour les comparaisons")
    
    async def get_weather_context(self, cities: List[str]) -> str:
        """Récupère le contexte météo pour toutes les villes"""
        weather_data = {}
        
        for city in cities:
            result = await self.mcp_server.get_weather(city)
            if result.get("success"):
                weather_data[city] = result["data"]
            else:
                weather_data[city] = {"error": result.get("error", "Unknown error")}
        
        # Construire le contexte
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
        
        return weather_context
    
    async def ask_claude(self, question: str, weather_context: str) -> Optional[str]:
        """Pose une question à Claude"""
        if not self.claude_client:
            return None
        
        try:
            response = self.claude_client.messages.create(
                model="claude-3-sonnet-20240229",
                max_tokens=1000,
                messages=[
                    {
                        "role": "user",
                        "content": f"{weather_context}\\n\\nQuestion: {question}"
                    }
                ]
            )
            return response.content[0].text
        except Exception as e:
            return f"Erreur Claude: {e}"
    
    async def ask_azure(self, question: str, weather_context: str) -> Optional[str]:
        """Pose une question à Azure OpenAI"""
        if not self.azure_client:
            return None
        
        try:
            response = self.azure_client.chat.completions.create(
                model=self.azure_deployment,
                messages=[
                    {
                        "role": "system",
                        "content": "Tu es un assistant météo expert. Réponds de manière précise et utile basé sur les données météo fournies."
                    },
                    {
                        "role": "user",
                        "content": f"{weather_context}\\n\\nQuestion: {question}"
                    }
                ],
                max_tokens=1000,
                temperature=0.7
            )
            return response.choices[0].message.content
        except Exception as e:
            return f"Erreur Azure: {e}"
    
    async def compare_responses(self, question: str, cities: List[str]):
        """Compare les réponses des deux IA"""
        print(f"\\n❓ Question: {question}")
        print(f"🌍 Villes: {', '.join(cities)}")
        print("-" * 60)
        
        # Récupérer le contexte météo
        weather_context = await self.get_weather_context(cities)
        
        # Afficher les données météo
        print("🌤️ Données météo récupérées:")
        for city in cities:
            result = await self.mcp_server.get_weather(city)
            if result.get("success"):
                data = result["data"]
                print(f"   {city}: {data['temperature']}{data['unit']}, {data['condition']}")
            else:
                print(f"   {city}: Erreur")
        
        results = {}
        
        # Test Claude
        if self.claude_client:
            print("\\n🧠 Test Claude...")
            start_time = time.time()
            claude_response = await self.ask_claude(question, weather_context)
            claude_time = time.time() - start_time
            
            results['claude'] = {
                'response': claude_response,
                'time': claude_time,
                'length': len(claude_response) if claude_response else 0
            }
        
        # Test Azure OpenAI
        if self.azure_client:
            print("🤖 Test Azure OpenAI...")
            start_time = time.time()
            azure_response = await self.ask_azure(question, weather_context)
            azure_time = time.time() - start_time
            
            results['azure'] = {
                'response': azure_response,
                'time': azure_time,
                'length': len(azure_response) if azure_response else 0
            }
        
        # Afficher les résultats
        if 'claude' in results:
            print(f"\\n🧠 CLAUDE ({results['claude']['time']:.2f}s, {results['claude']['length']} chars):")
            print("─" * 40)
            self._print_formatted_response(results['claude']['response'])
        
        if 'azure' in results:
            print(f"\\n🤖 AZURE OPENAI ({results['azure']['time']:.2f}s, {results['azure']['length']} chars):")
            print("─" * 40)
            self._print_formatted_response(results['azure']['response'])
        
        # Comparaison rapide
        if len(results) == 2:
            print(f"\\n⚡ COMPARAISON RAPIDE:")
            claude_faster = results['claude']['time'] < results['azure']['time']
            claude_longer = results['claude']['length'] > results['azure']['length']
            
            print(f"   🏃 Plus rapide: {'Claude' if claude_faster else 'Azure'}")
            print(f"   📝 Plus détaillé: {'Claude' if claude_longer else 'Azure'}")
            print(f"   ⏱️ Écart temps: {abs(results['claude']['time'] - results['azure']['time']):.2f}s")
        
        return results
    
    def _print_formatted_response(self, response: str):
        """Affiche une réponse formatée"""
        if not response:
            print("   (Aucune réponse)")
            return
        
        lines = response.split('\\n')
        for line in lines:
            if len(line) > 75:
                words = line.split(' ')
                current_line = ""
                for word in words:
                    if len(current_line + word) > 72:
                        print(f"   {current_line.strip()}")
                        current_line = word + " "
                    else:
                        current_line += word + " "
                if current_line.strip():
                    print(f"   {current_line.strip()}")
            else:
                print(f"   {line}")
    
    async def cleanup(self):
        """Nettoie les ressources"""
        if self.mcp_server:
            await self.mcp_server.stop()


async def run_comparison():
    """Exécute la comparaison complète"""
    
    comparator = AIComparator()
    
    try:
        await comparator.setup_mcp_server()
        
        # Questions de test comparatives
        test_scenarios = [
            {
                "question": "Quelle ville est idéale pour une promenade aujourd'hui ?",
                "cities": ["Paris", "London", "Madrid"]
            },
            {
                "question": "Dois-je reporter mon pique-nique prévu à New York ?",
                "cities": ["New York"]
            },
            {
                "question": "Compare la météo entre hémisphères nord et sud",
                "cities": ["Tokyo", "Sydney"]
            },
            {
                "question": "Planifie ma journée parfaite à Berlin selon la météo",
                "cities": ["Berlin"]
            }
        ]
        
        print(f"\\n🎯 COMPARAISON sur {len(test_scenarios)} scénarios")
        print("=" * 60)
        
        all_results = []
        
        for i, scenario in enumerate(test_scenarios, 1):
            print(f"\\n📋 SCÉNARIO {i}/{len(test_scenarios)}")
            print("=" * 60)
            
            results = await comparator.compare_responses(
                scenario['question'], 
                scenario['cities']
            )
            
            all_results.append({
                'scenario': i,
                'question': scenario['question'],
                'results': results
            })
            
            if i < len(test_scenarios):
                print("\\n⏳ Pause 3s...")
                await asyncio.sleep(3)
        
        # Résumé global
        print(f"\\n🏆 RÉSUMÉ GLOBAL")
        print("=" * 60)
        
        if all_results and len(all_results[0]['results']) == 2:
            claude_times = [r['results']['claude']['time'] for r in all_results]
            azure_times = [r['results']['azure']['time'] for r in all_results]
            claude_lengths = [r['results']['claude']['length'] for r in all_results]
            azure_lengths = [r['results']['azure']['length'] for r in all_results]
            
            print(f"📊 STATISTIQUES:")
            print(f"   Claude - Temps moyen: {sum(claude_times)/len(claude_times):.2f}s")
            print(f"   Azure  - Temps moyen: {sum(azure_times)/len(azure_times):.2f}s")
            print(f"   Claude - Longueur moyenne: {sum(claude_lengths)/len(claude_lengths):.0f} chars")
            print(f"   Azure  - Longueur moyenne: {sum(azure_lengths)/len(azure_lengths):.0f} chars")
            
            claude_wins_speed = sum(1 for c, a in zip(claude_times, azure_times) if c < a)
            print(f"\\n🏃 Vitesse: Claude gagne {claude_wins_speed}/{len(all_results)} fois")
        
        print(f"\\n✅ COMPARAISON TERMINÉE!")
        print(f"🎯 Les deux IA fonctionnent parfaitement avec votre serveur MCP!")
        
    except Exception as e:
        print(f"❌ Erreur: {e}")
        import traceback
        traceback.print_exc()
    finally:
        await comparator.cleanup()


if __name__ == "__main__":
    print(f"🔧 Workspace: {os.getcwd()}")
    
    available_apis = []
    if claude_available and ANTHROPIC_LIB:
        available_apis.append("Claude")
    if azure_available and OPENAI_LIB:
        available_apis.append("Azure OpenAI")
    
    if available_apis:
        print(f"🎯 APIs disponibles: {', '.join(available_apis)}")
        try:
            asyncio.run(run_comparison())
        except KeyboardInterrupt:
            print("\\n⚠️ Comparaison interrompue par l'utilisateur")
        except Exception as e:
            print(f"\\n❌ Erreur générale: {e}")
    else:
        print("❌ Aucune API disponible pour la comparaison")
        print("💡 Configurez au moins une API dans .env et installez les dépendances")