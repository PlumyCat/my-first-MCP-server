#!/usr/bin/env python3
"""
Script pour exécuter le serveur MCP localement sans Docker
Utile quand Docker a des problèmes de réseau
"""

import os
import sys
import asyncio
import subprocess
import json

def setup_python_path():
    """Configure le PYTHONPATH pour l'exécution locale"""
    current_dir = os.getcwd()
    src_dir = os.path.join(current_dir, 'src')
    
    if current_dir not in sys.path:
        sys.path.insert(0, current_dir)
    if src_dir not in sys.path:
        sys.path.insert(0, src_dir)
    
    # Variable d'environnement
    os.environ['PYTHONPATH'] = f"{current_dir}{os.pathsep}{src_dir}"
    
    print(f"✅ PYTHONPATH configuré:")
    print(f"   - {current_dir}")
    print(f"   - {src_dir}")

def install_dependencies():
    """Installe les dépendances localement"""
    print("📦 Installation des dépendances...")
    
    try:
        result = subprocess.run([
            sys.executable, "-m", "pip", "install", "-r", "requirements.txt"
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✅ Dépendances installées avec succès")
            return True
        else:
            print(f"❌ Erreur lors de l'installation: {result.stderr}")
            return False
    except Exception as e:
        print(f"❌ Exception lors de l'installation: {e}")
        return False

def test_weather_tool_direct():
    """Test direct de l'outil météo"""
    print("\n🧪 Test direct de l'outil météo...")
    
    try:
        # Import direct du module
        from src.tools.weather import WeatherTool
        
        async def run_test():
            tool = WeatherTool()
            
            # Test avec Paris
            result = await tool.execute("Paris", "celsius")
            print("✅ Test Paris réussi:")
            print(json.dumps(result, indent=2, ensure_ascii=False))
            
            # Test avec New York en Fahrenheit
            result2 = await tool.execute("New York", "fahrenheit")
            print("\n✅ Test New York réussi:")
            print(json.dumps(result2, indent=2, ensure_ascii=False))
            
            return True
        
        # Exécution du test async
        asyncio.run(run_test())
        return True
        
    except ImportError as e:
        print(f"❌ Erreur d'import: {e}")
        return False
    except Exception as e:
        print(f"❌ Erreur lors du test: {e}")
        return False

def run_mcp_server_local():
    """Lance le serveur MCP en mode local"""
    print("\n🚀 Lancement du serveur MCP local...")
    
    try:
        # Import et lancement du serveur
        from src.main import main
        
        print("📡 Serveur MCP démarré en mode local")
        print("   (Ctrl+C pour arrêter)")
        
        # Lancement du serveur
        asyncio.run(main())
        
    except KeyboardInterrupt:
        print("\n🛑 Serveur arrêté par l'utilisateur")
    except ImportError as e:
        print(f"❌ Erreur d'import du serveur: {e}")
    except Exception as e:
        print(f"❌ Erreur lors du lancement: {e}")

def main():
    """Fonction principale"""
    print("🌤️ Lancement du serveur MCP Weather en mode local")
    print("=" * 60)
    
    # Configuration du chemin Python
    setup_python_path()
    
    # Installation des dépendances
    if not install_dependencies():
        print("❌ Impossible d'installer les dépendances")
        return False
    
    # Test direct de l'outil
    if test_weather_tool_direct():
        print("✅ Tests directs réussis!")
    else:
        print("❌ Tests directs échoués")
        return False
    
    # Choix de l'utilisateur
    print("\n" + "="*60)
    print("📋 Options disponibles:")
    print("1. Lancer le serveur MCP complet (stdio)")
    print("2. Exécuter seulement les tests")
    print("3. Quitter")
    
    try:
        choice = input("\nChoisissez une option (1-3): ").strip()
        
        if choice == "1":
            run_mcp_server_local()
        elif choice == "2":
            print("✅ Tests terminés - voir les résultats ci-dessus")
        elif choice == "3":
            print("👋 Au revoir!")
        else:
            print("❌ Option invalide")
    
    except KeyboardInterrupt:
        print("\n👋 Au revoir!")
    
    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)