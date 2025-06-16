#!/usr/bin/env python3
"""
Test unifié du serveur MCP dans tous les environnements
Teste : Local -> Docker -> Azure avec Azure OpenAI/Claude API
"""

import os
import sys
import asyncio
import argparse
from dotenv import load_dotenv

# Charger les variables d'environnement
load_dotenv()

print("🌍 TEST MULTI-ENVIRONNEMENTS MCP WEATHER")
print("=" * 50)

# Importer les testeurs spécialisés
try:
    # Test local (serveurs existants)
    try:
        from test_azure_openai_api import AzureOpenAIWeatherTester
        HAS_AZURE_OPENAI_TESTER = True
    except ImportError:
        HAS_AZURE_OPENAI_TESTER = False

    try:
        from test_claude_api import ClaudeWeatherTester
        HAS_CLAUDE_TESTER = True
    except ImportError:
        HAS_CLAUDE_TESTER = False

    # Test Docker (nouveau)
    try:
        from test_docker_local import DockerTester, run_docker_tests
        HAS_DOCKER_TESTER = True
    except ImportError:
        HAS_DOCKER_TESTER = False

    # Test Azure (nouveau)
    try:
        from test_azure_deployment import AzureDeploymentTester, run_azure_deployment_tests
        HAS_AZURE_TESTER = True
    except ImportError:
        HAS_AZURE_TESTER = False

    available_testers = []
    if HAS_AZURE_OPENAI_TESTER:
        available_testers.append("Azure OpenAI")
    if HAS_CLAUDE_TESTER:
        available_testers.append("Claude")
    if HAS_DOCKER_TESTER:
        available_testers.append("Docker")
    if HAS_AZURE_TESTER:
        available_testers.append("Azure")

    print(
        f"✅ Testeurs disponibles: {', '.join(available_testers) if available_testers else 'Aucun'}")

except Exception as e:
    print(f"❌ Erreur d'import: {e}")
    print("💡 Certains modules de test ne sont pas disponibles")
    HAS_AZURE_OPENAI_TESTER = HAS_CLAUDE_TESTER = HAS_DOCKER_TESTER = HAS_AZURE_TESTER = False


class UnifiedTester:
    """Testeur unifié pour tous les environnements"""

    def __init__(self):
        self.results = {}

        # Vérifier les configurations disponibles
        self.has_azure_openai = all([
            os.getenv('AZURE_OPENAI_API_KEY'),
            os.getenv('AZURE_OPENAI_ENDPOINT'),
            os.getenv('AZURE_OPENAI_DEPLOYMENT_NAME')
        ])

        self.has_claude = bool(os.getenv('ANTHROPIC_API_KEY'))

        self.has_azure_deployment = all([
            os.getenv('AZURE_SERVER_URL'),
            os.getenv('AZURE_AD_TENANT_ID'),
            os.getenv('AZURE_AD_CLIENT_ID'),
            os.getenv('AZURE_AD_CLIENT_SECRET')
        ])

        self.has_weather_api = bool(os.getenv('OPENWEATHER_API_KEY'))

        print(f"🔧 Configuration détectée:")
        print(f"   🌤️ API Météo: {'✅' if self.has_weather_api else '❌'}")
        print(f"   🤖 Azure OpenAI: {'✅' if self.has_azure_openai else '❌'}")
        print(f"   🧠 Claude: {'✅' if self.has_claude else '❌'}")
        print(
            f"   ☁️ Azure Deployment: {'✅' if self.has_azure_deployment else '❌'}")

    async def test_local_environment(self) -> dict:
        """Teste l'environnement local"""
        print(f"\n🏠 TEST ENVIRONNEMENT LOCAL")
        print("=" * 40)

        if not self.has_weather_api:
            print("❌ API météo non configurée - test local impossible")
            return {"local": False, "reason": "No weather API"}

        local_results = {}

        # Test avec Azure OpenAI
        if self.has_azure_openai and HAS_AZURE_OPENAI_TESTER:
            print("\n🤖 Test local avec Azure OpenAI...")
            try:
                tester = AzureOpenAIWeatherTester()
                await tester.setup_mcp_server()

                # Test simple
                response = await tester.ask_azure_with_weather(
                    "Quelle est la météo à Paris ?",
                    ["Paris"]
                )

                local_results['azure_openai'] = len(response) > 50
                print(f"   ✅ Test réussi: {len(response)} caractères")

                await tester.cleanup()

            except Exception as e:
                print(f"   ❌ Erreur: {e}")
                local_results['azure_openai'] = False
        elif self.has_azure_openai and not HAS_AZURE_OPENAI_TESTER:
            print("\n⚠️ Azure OpenAI configuré mais testeur non disponible")

        # Test avec Claude
        if self.has_claude and HAS_CLAUDE_TESTER:
            print("\n🧠 Test local avec Claude...")
            try:
                tester = ClaudeWeatherTester()
                await tester.setup_mcp_server()

                # Test simple
                response = await tester.ask_claude_with_weather(
                    "Quelle est la météo à Londres ?",
                    ["London"]
                )

                local_results['claude'] = len(response) > 50
                print(f"   ✅ Test réussi: {len(response)} caractères")

                await tester.cleanup()

            except Exception as e:
                print(f"   ❌ Erreur: {e}")
                local_results['claude'] = False
        elif self.has_claude and not HAS_CLAUDE_TESTER:
            print("\n⚠️ Claude configuré mais testeur non disponible")

        success = any(local_results.values()) if local_results else False
        return {"local": success, "local_details": local_results}

    async def test_docker_environment(self) -> dict:
        """Teste l'environnement Docker"""
        print(f"\n🐳 TEST ENVIRONNEMENT DOCKER")
        print("=" * 40)

        if not self.has_weather_api:
            print("❌ API météo non configurée - test Docker impossible")
            return {"docker": False, "reason": "No weather API"}

        if not HAS_DOCKER_TESTER:
            print("❌ Testeur Docker non disponible")
            return {"docker": False, "reason": "Docker tester not available"}

        try:
            # Importer et utiliser la fonction directement
            results = await run_docker_tests()

            success = sum(results.values()) >= len(results) // 2
            return {"docker": success, "docker_details": results}

        except Exception as e:
            print(f"❌ Erreur Docker: {e}")
            return {"docker": False, "reason": str(e)}

    async def test_azure_environment(self) -> dict:
        """Teste l'environnement Azure"""
        print(f"\n☁️ TEST ENVIRONNEMENT AZURE")
        print("=" * 40)

        if not self.has_azure_deployment:
            print("❌ Déploiement Azure non configuré - test ignoré")
            return {"azure": False, "reason": "No Azure deployment config"}

        if not HAS_AZURE_TESTER:
            print("❌ Testeur Azure non disponible")
            return {"azure": False, "reason": "Azure tester not available"}

        try:
            # Importer et utiliser la fonction directement
            results = await run_azure_deployment_tests()

            success = sum(results.values()) >= len(results) // 2
            return {"azure": success, "azure_details": results}

        except Exception as e:
            print(f"❌ Erreur Azure: {e}")
            return {"azure": False, "reason": str(e)}

    async def run_all_tests(self, environments: list = None) -> dict:
        """Exécute tous les tests demandés"""

        if environments is None:
            environments = ['local', 'docker', 'azure']

        print(f"\n🎯 TESTS MULTI-ENVIRONNEMENTS")
        print(f"Environnements: {', '.join(environments)}")
        print("=" * 50)

        all_results = {}

        # Test local
        if 'local' in environments:
            all_results.update(await self.test_local_environment())

        # Test Docker
        if 'docker' in environments:
            all_results.update(await self.test_docker_environment())

        # Test Azure
        if 'azure' in environments:
            all_results.update(await self.test_azure_environment())

        return all_results

    def print_final_summary(self, results: dict):
        """Affiche le résumé final"""
        print(f"\n🎉 RÉSUMÉ FINAL MULTI-ENVIRONNEMENTS")
        print("=" * 50)

        environment_names = {
            'local': '🏠 Local',
            'docker': '🐳 Docker',
            'azure': '☁️ Azure'
        }

        success_count = 0
        total_count = 0

        for env_key, success in results.items():
            if env_key in environment_names:
                total_count += 1
                if success:
                    success_count += 1

                status = "✅ RÉUSSI" if success else "❌ ÉCHEC"
                print(f"   {environment_names[env_key]}: {status}")

                # Détails si disponibles
                details_key = env_key + '_details'
                if details_key in results:
                    details = results[details_key]
                    if isinstance(details, dict):
                        for test_name, test_success in details.items():
                            test_status = "✅" if test_success else "❌"
                            print(f"      {test_status} {test_name}")

        print(f"\n📊 Score global: {success_count}/{total_count}")

        if success_count == total_count:
            print("🎉 Tous les environnements fonctionnent parfaitement !")
        elif success_count > 0:
            print(f"✅ {success_count} environnement(s) fonctionnel(s)")
        else:
            print("⚠️ Aucun environnement ne fonctionne correctement")

        # Recommandations
        print(f"\n💡 RECOMMANDATIONS:")
        if results.get('local'):
            print("   ✅ Développement local prêt")
        else:
            print("   ⚠️ Configurez l'environnement local pour le développement")

        if results.get('docker'):
            print("   ✅ Container Docker fonctionnel")
        else:
            print("   ⚠️ Vérifiez la configuration Docker")

        if results.get('azure'):
            print("   ✅ Déploiement Azure opérationnel")
        else:
            print("   ⚠️ Déploiement Azure à configurer/corriger")


async def main():
    """Fonction principale"""

    parser = argparse.ArgumentParser(
        description='Test multi-environnements MCP Weather')
    parser.add_argument('--env', choices=['local', 'docker', 'azure'],
                        action='append', help='Environnements à tester')
    parser.add_argument('--all', action='store_true',
                        help='Tester tous les environnements')

    args = parser.parse_args()

    # Déterminer les environnements à tester
    if args.all or not args.env:
        environments = ['local', 'docker', 'azure']
    else:
        environments = args.env

    print(f"🎯 Environnements sélectionnés: {', '.join(environments)}")

    # Exécuter les tests
    tester = UnifiedTester()
    results = await tester.run_all_tests(environments)

    # Afficher le résumé
    tester.print_final_summary(results)

    return results


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n⚠️ Tests interrompus par l'utilisateur")
    except Exception as e:
        print(f"\n❌ Erreur générale: {e}")
        import traceback
        traceback.print_exc()
