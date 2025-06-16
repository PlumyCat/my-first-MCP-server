#!/usr/bin/env python3
"""
Serveur HTTP pour MCP Weather (utilisé pour les tests Docker)
"""
import json
import logging
import os
import asyncio
from typing import Dict, Any
from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from .server import create_mcp_server
# Import conditionnel de l'auth Azure AD
try:
    from .auth import verify_azure_token
    HAS_AZURE_AUTH = True
except Exception:
    HAS_AZURE_AUTH = False

    async def verify_azure_token(token):
        return None

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Création de l'application FastAPI
app = FastAPI(
    title="MCP Weather Server",
    description="Serveur HTTP pour MCP Weather avec authentification Azure AD",
    version="1.0.0"
)

# Instance globale du serveur MCP
mcp_server = None


class MCPRequest(BaseModel):
    """Modèle pour les requêtes MCP"""
    jsonrpc: str = "2.0"
    id: int
    method: str
    params: Dict[str, Any] = {}


class MCPToolCall(BaseModel):
    """Modèle pour les appels d'outils MCP"""
    name: str
    arguments: Dict[str, Any]


async def get_mcp_server():
    """Obtient l'instance du serveur MCP"""
    global mcp_server
    if mcp_server is None:
        mcp_server = create_mcp_server()
        logger.info("Serveur MCP initialisé")
    return mcp_server


async def verify_auth(request: Request):
    """Vérifie l'authentification si Azure AD est configuré"""
    # Vérifier si l'authentification Azure AD est activée
    if not HAS_AZURE_AUTH or not all([
        os.getenv('AZURE_AD_TENANT_ID'),
        os.getenv('AZURE_AD_CLIENT_ID'),
        os.getenv('AZURE_AD_CLIENT_SECRET')
    ]):
        # Pas d'auth configurée, autoriser
        logger.info("Authentification Azure AD désactivée")
        return True

    # Extraire le token Bearer
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        raise HTTPException(
            status_code=401, detail="Token d'authentification requis")

    token = auth_header.split(' ')[1]

    # Vérifier le token Azure AD
    try:
        user_info = await verify_azure_token(token)
        return user_info
    except Exception as e:
        logger.error(f"Erreur d'authentification: {e}")
        raise HTTPException(status_code=401, detail="Token invalide")


@app.get("/health")
async def health_check():
    """Endpoint de santé"""
    return {"status": "healthy", "service": "mcp-weather-server"}


@app.get("/")
async def root():
    """Endpoint racine"""
    return {
        "service": "MCP Weather Server",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "mcp": "/mcp",
            "tools": "/tools"
        }
    }


@app.get("/tools")
async def list_tools(auth=Depends(verify_auth)):
    """Liste les outils disponibles"""
    try:
        server = await get_mcp_server()

        # Simuler un appel list_tools
        tools = []

        # Outil météo
        tools.append({
            "name": "get_weather",
            "description": "Récupère les informations météorologiques pour une ville donnée",
            "parameters": {
                "type": "object",
                "properties": {
                    "city": {
                        "type": "string",
                        "description": "Nom de la ville"
                    },
                    "unit": {
                        "type": "string",
                        "enum": ["celsius", "fahrenheit"],
                        "default": "celsius",
                        "description": "Unité de température"
                    }
                },
                "required": ["city"]
            }
        })

        return {"tools": tools}

    except Exception as e:
        logger.error(f"Erreur lors de la liste des outils: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/mcp")
async def handle_mcp_request(request: MCPRequest, auth=Depends(verify_auth)):
    """Gestionnaire principal pour les requêtes MCP"""
    try:
        logger.info(f"Requête MCP: {request.method}")

        if request.method == "tools/call":
            return await handle_tool_call(request)
        elif request.method == "tools/list":
            return await handle_list_tools(request)
        elif request.method == "initialize":
            return await handle_initialize(request)
        else:
            raise HTTPException(
                status_code=400, detail=f"Méthode non supportée: {request.method}")

    except Exception as e:
        logger.error(f"Erreur lors du traitement de la requête MCP: {e}")
        return JSONResponse(
            status_code=500,
            content={
                "jsonrpc": "2.0",
                "id": request.id,
                "error": {
                    "code": -32603,
                    "message": "Erreur interne du serveur",
                    "data": str(e)
                }
            }
        )


async def handle_initialize(request: MCPRequest):
    """Gestionnaire pour l'initialisation MCP"""
    return {
        "jsonrpc": "2.0",
        "id": request.id,
        "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {}
            },
            "serverInfo": {
                "name": "mcp-weather-server",
                "version": "1.0.0"
            }
        }
    }


async def handle_list_tools(request: MCPRequest):
    """Gestionnaire pour lister les outils"""
    tools = [
        {
            "name": "get_weather",
            "description": "Récupère les informations météorologiques pour une ville donnée",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "city": {
                        "type": "string",
                        "description": "Nom de la ville"
                    },
                    "unit": {
                        "type": "string",
                        "enum": ["celsius", "fahrenheit"],
                        "default": "celsius",
                        "description": "Unité de température"
                    }
                },
                "required": ["city"]
            }
        }
    ]

    return {
        "jsonrpc": "2.0",
        "id": request.id,
        "result": {
            "tools": tools
        }
    }


async def handle_tool_call(request: MCPRequest):
    """Gestionnaire pour les appels d'outils"""
    try:
        server = await get_mcp_server()

        # Extraire les paramètres
        tool_name = request.params.get("name")
        arguments = request.params.get("arguments", {})

        if not tool_name:
            raise ValueError("Nom de l'outil requis")

        if tool_name == "get_weather":
            # Importer et utiliser l'outil météo directement
            from .tools.weather import WeatherTool
            weather_tool = WeatherTool()

            city = arguments.get("city")
            unit = arguments.get("unit", "celsius")

            if not city:
                raise ValueError("Le paramètre 'city' est requis")

            # Exécuter l'outil
            result = await weather_tool.execute(city, unit)

            return {
                "jsonrpc": "2.0",
                "id": request.id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(result, ensure_ascii=False)
                        }
                    ]
                }
            }
        else:
            raise ValueError(f"Outil inconnu: {tool_name}")

    except Exception as e:
        logger.error(f"Erreur lors de l'appel d'outil: {e}")
        return {
            "jsonrpc": "2.0",
            "id": request.id,
            "error": {
                "code": -32603,
                "message": "Erreur lors de l'exécution de l'outil",
                "data": str(e)
            }
        }


if __name__ == "__main__":
    import uvicorn

    # Configuration du serveur
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))

    logger.info(f"Démarrage du serveur HTTP MCP sur {host}:{port}")

    # Démarrage du serveur
    uvicorn.run(
        "src.http_server:app",
        host=host,
        port=port,
        log_level="info",
        access_log=True
    )
