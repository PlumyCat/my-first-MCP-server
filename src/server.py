"""
Serveur MCP principal
"""
import json
import logging
from typing import Any, Dict, List
from mcp.server import Server
from mcp.types import Tool, TextContent, CallToolResult
from .tools import WeatherTool

# Configuration du logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class MCPWeatherServer:
    """Serveur MCP pour les données météo"""
    
    def __init__(self):
        self.server = Server("weather-mcp-server")
        self.weather_tool = WeatherTool()
        self._setup_tools()
    
    def _setup_tools(self):
        """Configure les outils disponibles"""
        # Définition de l'outil météo
        weather_tool_def = Tool(
            name=self.weather_tool.name,
            description=self.weather_tool.description,
            inputSchema=self.weather_tool.parameters
        )
        
        # Enregistrement du handler pour l'outil météo
        @self.server.call_tool()
        async def handle_call_tool(name: str, arguments: Dict[str, Any]) -> List[TextContent]:
            """Gestionnaire d'appel d'outil"""
            logger.info(f"Appel de l'outil: {name} avec arguments: {arguments}")
            
            if name == "get_weather":
                try:
                    city = arguments.get("city", "")
                    unit = arguments.get("unit", "celsius")
                    
                    if not city:
                        return [TextContent(
                            type="text", 
                            text=json.dumps({
                                "error": "Le paramètre 'city' est requis"
                            })
                        )]
                    
                    # Exécution de l'outil météo
                    result = await self.weather_tool.execute(city, unit)
                    
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2, ensure_ascii=False)
                    )]
                    
                except Exception as e:
                    logger.error(f"Erreur lors de l'exécution de l'outil météo: {e}")
                    return [TextContent(
                        type="text",
                        text=json.dumps({
                            "error": f"Erreur lors de l'exécution: {str(e)}"
                        })
                    )]
            else:
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Outil inconnu: {name}"
                    })
                )]
        
        # Enregistrement de la liste des outils
        @self.server.list_tools()
        async def handle_list_tools() -> List[Tool]:
            """Retourne la liste des outils disponibles"""
            logger.info("Demande de liste des outils")
            return [weather_tool_def]
    
    def get_server(self) -> Server:
        """Retourne l'instance du serveur MCP"""
        return self.server


def create_mcp_server() -> Server:
    """Factory pour créer le serveur MCP"""
    logger.info("Création du serveur MCP Weather")
    weather_server = MCPWeatherServer()
    return weather_server.get_server()