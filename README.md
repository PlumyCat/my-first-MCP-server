# 🌤️ My First MCP - Weather Server

A complete MCP (Model Context Protocol) server that provides weather data for AI assistants like Claude Desktop. This project is perfect for learning how to create custom MCP servers and integrate them with AI applications.

## 📋 Table of Contents

- [📋 Table of Contents](#-table-of-contents)
- [🎯 What is an MCP Server?](#-what-is-an-mcp-server)
- [✨ Features](#-features)
- [🏗️ Project Structure](#️-project-structure)
- [⚡ Quick Start](#-quick-start)
- [🔧 Detailed Installation](#-detailed-installation)
  - [1. Prerequisites](#1-prerequisites)
  - [2. Clone the Project](#2-clone-the-project)
  - [3. Install Dependencies](#3-install-dependencies)
- [🚀 Usage](#-usage)
  - [Method 1: Docker (Recommended)](#method-1-docker-recommended)
  - [Method 2: Local Python](#method-2-local-python)
- [🧪 Testing and Validation](#-testing-and-validation)
- [🤖 AI Integration](#-ai-integration)
  - [Claude Desktop](#claude-desktop)
  - [Azure OpenAI](#azure-openai)
  - [Claude API](#claude-api)
- [📚 API Documentation](#-api-documentation)
- [🔍 Troubleshooting](#-troubleshooting)
- [🛠️ Development](#️-development)
- [📈 Next Steps](#-next-steps)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

## 🎯 What is an MCP Server?

The **Model Context Protocol (MCP)** is a standardized protocol that allows AI assistants to interact with external tools. This weather server is a practical example that:

- 🔌 Connects to Claude Desktop or other AI clients
- 🌍 Provides mock weather data for any city worldwide
- 📡 Communicates via JSON-RPC over stdin/stdout
- 🛠️ Exposes tools that AI can use automatically

## ✨ Features

### 🌤️ Core Weather Tool
- **Complete Data**: Temperature, humidity, wind, pressure, visibility, UV index
- **Multi-unit Support**: Celsius and Fahrenheit
- **Forecasts**: Includes 2-day weather predictions
- **Realistic Data**: Intelligent generation of coherent weather patterns

### 🔧 Technical Features
- **MCP Protocol**: Compliant with 2024-11-05 standard
- **JSON-RPC**: Standardized communication
- **Docker Support**: Containerized deployment
- **Comprehensive Testing**: Full test suite included
- **Detailed Logging**: Complete logging system

### 🤖 AI Integrations
- **Claude Desktop**: Automatic configuration
- **Azure OpenAI**: Testing and integration examples
- **Claude API**: Dedicated test scripts
- **Standard Format**: Compatible with any MCP client

## 🏗️ Project Structure

```
my_first_mcp/
├── 📁 src/                     # Main source code
│   ├── __init__.py
│   ├── main.py                 # MCP entry point
│   ├── server.py               # MCP server configuration
│   ├── auth.py                 # Azure AD auth (optional)
│   └── 📁 tools/
│       ├── __init__.py
│       └── weather.py          # Main weather tool
├── 📁 test/                    # Test scripts
│   ├── test_mcp_server.py      # Complete server test
│   ├── test_claude_api.py      # Claude API test
│   ├── test_azure_openai_api.py # Azure OpenAI test
│   ├── compare_ai_apis.py      # Claude vs Azure comparison
│   ├── run_local.py            # Local execution
│   └── test_with_ai.py         # AI configuration
├── 📄 requirements.txt         # Python dependencies
├── 🐳 Dockerfile              # Main Docker image
├── 🐳 Dockerfile.local        # Alternative Docker image
├── 🐳 docker-compose.yml      # Docker orchestration
├── 📄 .gitignore              # Ignored files
├── 📄 env_example.txt         # Environment variables
├── 📄 mcp_config_example.json # MCP configuration example
└── 📖 README.md               # This file
```

## ⚡ Quick Start

```bash
# 1. Clone the project
git clone <your-repo> my_first_mcp
cd my_first_mcp

# 2. Start with Docker (recommended)
docker-compose up --build

# 3. Test the server
python test/test_mcp_server.py
```

## 🔧 Detailed Installation

### 1. Prerequisites

#### 🐍 Python 3.11+
```bash
# Check Python version
python --version
# Should display Python 3.11.x or newer
```

**Install Python:**
- **Windows**: [python.org/downloads](https://www.python.org/downloads/)
- **macOS**: `brew install python` or [python.org](https://www.python.org/downloads/)
- **Linux**: `sudo apt update && sudo apt install python3.11 python3.11-pip`

#### 🐳 Docker (optional but recommended)
```bash
# Check Docker
docker --version
docker-compose --version
```

**Install Docker:**
- **Windows/macOS**: [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- **Linux**: [Official Instructions](https://docs.docker.com/engine/install/)

#### 📦 Git
```bash
# Check Git
git --version
```

**Install Git:**
- **Windows**: [git-scm.com](https://git-scm.com/downloads)
- **macOS**: `brew install git` or Xcode Command Line Tools
- **Linux**: `sudo apt install git`

### 2. Clone the Project

```bash
# Clone from your repository
git clone <YOUR_REPO_URL> my_first_mcp

# Or create a new folder
mkdir my_first_mcp
cd my_first_mcp

# Copy all project files to this folder
```

### 3. Install Dependencies

#### Option A: Virtual Environment (recommended)
```bash
# Create virtual environment
python -m venv .venv

# Activate virtual environment
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

# Install dependencies
pip install --upgrade pip
pip install -r requirements.txt
```

#### Option B: Global Installation
```bash
# Direct installation (not recommended for production)
pip install -r requirements.txt
```

#### 📋 Key Dependencies
- **mcp**: Official MCP library
- **pydantic**: Data validation
- **asyncio-mqtt**: Asynchronous communication
- **anthropic**: Claude API (optional)
- **openai**: Azure OpenAI API (optional)
- **python-dotenv**: Environment variables

## 🚀 Usage

### Method 1: Docker (Recommended)

#### Simple Start
```bash
# Build and start
docker-compose up --build

# Run in background
docker-compose up -d --build

# View logs
docker logs mcp-weather-server -f

# Stop
docker-compose down
```

#### Network Issues?
```bash
# Use alternative version
docker-compose --profile alternative up --build
```

### Method 2: Local Python

#### Start the Server
```bash
# Activate virtual environment
source .venv/bin/activate  # or .venv\Scripts\activate on Windows

# Start MCP server
python -m src.main
```

#### Local Startup Script
```bash
# Use local test script
python test/run_local.py
```

### Method 3: Azure Cloud Deployment

#### Déploiement automatique sur Azure Container Instances

Le projet inclut des scripts PowerShell pour déployer automatiquement votre serveur MCP Weather sur Azure.

##### Prérequis
- Azure CLI installé
- Docker installé
- Compte Azure actif

##### Configuration rapide
```powershell
# 1. Vérifier les prérequis
.\azure-setup.ps1 -CheckOnly

# 2. Installer les prérequis automatiquement (Windows)
.\azure-setup.ps1 -InstallPrerequisites

# 3. Se connecter à Azure
az login
```

##### Déploiement
```powershell
# Déploiement simple (nom de registre requis - doit être unique)
.\deploy-azure.ps1 -ContainerRegistryName "mcpweather1234"

# Déploiement avec paramètres personnalisés
.\deploy-azure.ps1 -ContainerRegistryName "monregistre" -ResourceGroupName "mon-rg" -Location "France Central"
```

##### Gestion post-déploiement
```powershell
# Voir l'état du conteneur
.\azure-manage.ps1 -Action status

# Voir les logs en temps réel
.\azure-manage.ps1 -Action logs -Follow

# Redémarrer le conteneur
.\azure-manage.ps1 -Action restart

# Arrêter/démarrer le conteneur
.\azure-manage.ps1 -Action stop
.\azure-manage.ps1 -Action start

# Supprimer complètement le déploiement
.\azure-manage.ps1 -Action delete
```

##### Avantages du déploiement Azure
- ✅ **Haute disponibilité**: Redémarrage automatique
- ✅ **Scalabilité**: Ajustement des ressources
- ✅ **Sécurité**: Registre de conteneurs privé
- ✅ **Monitoring**: Logs et métriques intégrés
- ✅ **Coût optimisé**: Paiement à l'usage

## 🧪 Testing and Validation

### Complete Server Test
```bash
# Perfect final test - validated ✅
python test/test_mcp_server.py
```

**This test verifies:**
- ✅ MCP server startup
- ✅ Protocol initialization
- ✅ Available tools listing
- ✅ Tool calls with different cities
- ✅ JSON response format
- ✅ Performance statistics

### Specialized Tests

#### Simple Local Test
```bash
# Test without MCP, just the weather tool
python test/run_local.py
```

#### AI Configuration
```bash
# Automatically configures for Claude Desktop
python test/test_with_ai.py
```

## 🤖 AI Integration

### Claude Desktop

#### 1. Automatic Configuration
```bash
# Automatically configures Claude Desktop
python test/test_with_ai.py
```

#### 2. Manual Configuration
Edit `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "weather-server": {
      "command": "python",
      "args": ["-m", "src.main"],
      "cwd": "C:\\path\\to\\my_first_mcp",
      "env": {
        "PYTHONPATH": "C:\\path\\to\\my_first_mcp",
        "PYTHONUNBUFFERED": "1"
      }
    }
  }
}
```

#### 3. Usage in Claude
```
🗣️ "Can you give me the weather for Paris?"
🗣️ "Compare weather between London and Madrid"
🗣️ "Should I bring an umbrella in New York?"
```

### Azure OpenAI

#### 1. Environment Variables Setup
```bash
# Copy example file
cp env_example.txt .env

# Edit .env with your real keys
AZURE_OPENAI_API_KEY=your_key_here
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/
AZURE_OPENAI_DEPLOYMENT_NAME=your_deployment_name
```

#### 2. Test with Azure OpenAI
```bash
# Complete test with Azure OpenAI
python test/test_azure_openai_api.py
```

**Azure Prerequisites:**
- 🔑 [Azure Account](https://azure.microsoft.com/en-us/free/)
- 🧠 [Azure OpenAI Service](https://azure.microsoft.com/en-us/products/ai-services/openai-service)
- 🚀 GPT-4 or GPT-3.5-turbo deployment

### Claude API

#### 1. Configuration
```bash
# Add to .env
ANTHROPIC_API_KEY=sk-ant-api03-...
```

#### 2. Test with Claude API
```bash
# Complete test with Claude API
python test/test_claude_api.py
```

**Get Claude Key:**
- 🔗 [console.anthropic.com](https://console.anthropic.com/)
- 💳 Free credits available for new accounts

### AI Comparison

```bash
# Compare Claude vs Azure OpenAI side by side
python test/compare_ai_apis.py
```

## 📚 API Documentation

### `get_weather` Tool

#### Parameters
```json
{
  "city": "string (required)",
  "unit": "celsius|fahrenheit (optional, default: celsius)"
}
```

#### Example Call
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "get_weather",
    "arguments": {
      "city": "Paris",
      "unit": "celsius"
    }
  }
}
```

#### Example Response
```json
{
  "success": true,
  "data": {
    "city": "Paris",
    "temperature": 22,
    "unit": "°C",
    "condition": "sunny",
    "humidity": 65,
    "wind_speed": 12,
    "wind_unit": "km/h",
    "pressure": 1013,
    "visibility": 10,
    "uv_index": 6,
    "timestamp": "2025-06-16T14:30:00",
    "forecast": [
      {
        "day": "Tomorrow",
        "high": 25,
        "low": 15,
        "condition": "partly cloudy"
      },
      {
        "day": "Day after tomorrow",
        "high": 23,
        "low": 12,
        "condition": "rainy"
      }
    ]
  },
  "message": "Weather data retrieved for Paris"
}
```

### Supported MCP Messages

- `initialize`: Protocol initialization
- `tools/list`: List available tools
- `tools/call`: Call a tool
- `notifications/initialized`: Initialization notification

## 🔍 Troubleshooting

### Common Issues

#### "Module not found" Error
```bash
# Check PYTHONPATH
echo $PYTHONPATH  # Linux/macOS
echo %PYTHONPATH%  # Windows

# Reinstall dependencies
pip install -r requirements.txt --force-reinstall
```

#### Docker Won't Start
```bash
# Check Docker
docker --version
docker-compose --version

# Clean Docker
docker system prune -f
docker-compose down --volumes

# Rebuild
docker-compose up --build --force-recreate
```

#### Claude Desktop Doesn't See Server
1. ✅ Check path in `claude_desktop_config.json`
2. ✅ Restart Claude Desktop completely
3. ✅ Test server with `python test/test_mcp_server.py`
4. ✅ Check Claude Desktop logs

#### Missing Environment Variables
```bash
# Copy example file
cp env_example.txt .env

# Edit with your real values
nano .env  # or notepad .env on Windows
```

### Logs and Debugging

#### MCP Server Logs
```bash
# Local mode
python -m src.main

# Docker mode
docker logs mcp-weather-server -f
```

#### Claude Desktop Logs
- **Windows**: `%APPDATA%\Claude\logs\`
- **macOS**: `~/Library/Logs/Claude/`

#### Diagnostic Tests
```bash
# Complete test
python test/test_mcp_server.py

# Local only test
python test/run_local.py

# Configuration test
python test/test_with_ai.py
```

## 🛠️ Development

### Development Setup

```bash
# Development mode with auto-reload
docker-compose up --build

# Volumes are configured for hot reload
# Modify src/ and restart container
```

### Adding a New Tool

1. **Create the tool** in `src/tools/`
```python
# src/tools/my_tool.py
class MyTool:
    def __init__(self):
        self.name = "my_tool"
        self.description = "Description of my tool"
        self.parameters = {
            "type": "object",
            "properties": {
                "param1": {"type": "string", "description": "First parameter"}
            },
            "required": ["param1"]
        }
    
    async def execute(self, param1: str):
        return {"success": True, "result": f"Result for {param1}"}
```

2. **Register the tool** in `src/server.py`
```python
from .tools.my_tool import MyTool

# In MCPWeatherServer class
self.my_tool = MyTool()
# Add handler in _setup_tools()
```

3. **Test the tool**
```bash
python test/test_mcp_server.py
```

### Custom Tests

```python
# Create a custom test
import asyncio
from src.tools.weather import WeatherTool

async def test_custom():
    tool = WeatherTool()
    result = await tool.execute("Tokyo", "fahrenheit")
    print(f"Result: {result}")

asyncio.run(test_custom())
```

## 📈 Next Steps

### 🛠️ Additional Tools
- [ ] **News**: News API integration
- [ ] **Calculator**: Advanced mathematical tools
- [ ] **Translation**: Translation API
- [ ] **Database**: Persistent storage

### ☁️ Cloud Deployment
- [x] **Azure Container Instances**: Azure deployment (scripts inclus)
- [ ] **Azure Functions**: Serverless MCP

### 🔒 Security and Production
- [ ] **Authentication**: Azure AD, OAuth2
- [ ] **Rate Limiting**: Request throttling
- [ ] **Monitoring**: Metrics and alerts
- [ ] **HTTPS**: Secure communications

### 📚 Learning Resources
- 📖 [Official MCP Documentation](https://modelcontextprotocol.io/)
- 🧠 [Claude API Documentation](https://docs.anthropic.com/)
- 🤖 [Azure OpenAI Documentation](https://docs.microsoft.com/en-us/azure/ai-services/openai/)
- 🐳 [Docker Documentation](https://docs.docker.com/)

## 🤝 Contributing

### How to Contribute

1. **Fork** the project
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -am 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Create** a Pull Request

### Contributing Guidelines

- ✅ Tests required for all new features
- ✅ Updated documentation
- ✅ Python code follows PEP 8
- ✅ Descriptive commit messages
- ✅ Python 3.11+ compatibility

### Report a Bug

1. 🔍 Check if the bug already exists
2. 🐛 Use GitHub issue template
3. 📝 Include logs and reproduction steps
4. 🖥️ Specify environment (OS, Python, Docker)

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.

---

## 🎉 Congratulations!

You now have a complete and functional MCP Weather server!

🚀 **Production Ready** with Docker  
🧠 **Claude Desktop Compatible** for immediate use  
🤖 **Integrable** with Azure OpenAI and Claude API  
🔧 **Extensible** to add your own tools  

**Next Step**: Integrate a real weather API and deploy your server to the cloud!

---

## 🌟 Show Your Support

If this project helped you learn MCP, please give it a star ⭐️

- 🐛 **Found a bug?** [Open an issue](../../issues)
- 💡 **Have an idea?** [Start a discussion](../../discussions)
- 🤝 **Want to contribute?** [Read our guidelines](#-contributing)

---

*Created with ❤️ to learn the MCP protocol*
