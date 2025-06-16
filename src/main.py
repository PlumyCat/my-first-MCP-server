#!/usr/bin/env python3
"""
Point d'entrée principal du serveur MCP Weather
"""
import asyncio
import logging
import sys
from mcp.server.stdio import stdio_server
from .server import create_mcp_server

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


async def main():
    """Fonction principale du serveur MCP"""
    logger.info("Démarrage du serveur MCP Weather...")
    
    try:
        # Création du serveur MCP
        server = create_mcp_server()
        logger.info("Serveur MCP créé avec succès")
        
        # Démarrage du serveur avec stdio
        async with stdio_server() as (read_stream, write_stream):
            logger.info("Serveur MCP en écoute sur stdio...")
            await server.run(
                read_stream,
                write_stream,
                server.create_initialization_options()
            )
            
    except KeyboardInterrupt:
        logger.info("Arrêt du serveur demandé par l'utilisateur")
    except Exception as e:
        logger.error(f"Erreur lors du démarrage du serveur: {e}")
        sys.exit(1)
    finally:
        logger.info("Serveur MCP arrêté")


if __name__ == "__main__":
    # Point d'entrée pour l'exécution directe
    asyncio.run(main())