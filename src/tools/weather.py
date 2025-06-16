"""
Outil météo factice pour le serveur MCP
"""
import json
import random
from typing import Dict, Any
from datetime import datetime


class WeatherTool:
    """Outil pour récupérer des données météo factices"""
    
    def __init__(self):
        self.name = "get_weather"
        self.description = "Récupère les conditions météorologiques pour une ville donnée"
        self.parameters = {
            "type": "object",
            "properties": {
                "city": {
                    "type": "string",
                    "description": "Nom de la ville pour laquelle récupérer la météo"
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
    
    async def execute(self, city: str, unit: str = "celsius") -> Dict[str, Any]:
        """
        Exécute l'outil météo et retourne des données factices
        """
        # Données météo factices
        weather_conditions = [
            "ensoleillé", "nuageux", "pluvieux", "orageux", 
            "partiellement nuageux", "brumeux", "neigeux"
        ]
        
        # Température aléatoire selon l'unité
        if unit == "fahrenheit":
            temp = random.randint(32, 95)
            temp_unit = "°F"
        else:
            temp = random.randint(0, 35)
            temp_unit = "°C"
        
        # Génération des données factices
        weather_data = {
            "city": city,
            "temperature": temp,
            "unit": temp_unit,
            "condition": random.choice(weather_conditions),
            "humidity": random.randint(30, 90),
            "wind_speed": random.randint(5, 30),
            "wind_unit": "km/h",
            "pressure": random.randint(980, 1030),
            "visibility": random.randint(5, 15),
            "uv_index": random.randint(1, 10),
            "timestamp": datetime.now().isoformat(),
            "forecast": [
                {
                    "day": "Demain",
                    "high": temp + random.randint(-5, 5),
                    "low": temp - random.randint(5, 15),
                    "condition": random.choice(weather_conditions)
                },
                {
                    "day": "Après-demain", 
                    "high": temp + random.randint(-8, 8),
                    "low": temp - random.randint(3, 12),
                    "condition": random.choice(weather_conditions)
                }
            ]
        }
        
        return {
            "success": True,
            "data": weather_data,
            "message": f"Données météo récupérées pour {city}"
        }