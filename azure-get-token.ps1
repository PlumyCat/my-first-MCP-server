#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Script pour obtenir un token Azure AD et tester le serveur MCP sécurisé
.DESCRIPTION
    Ce script obtient un token d'accès Azure AD et teste l'authentification du serveur MCP Weather
.PARAMETER TenantId
    Azure AD Tenant ID
.PARAMETER ClientId
    Azure AD Client ID (Application ID)
.PARAMETER ClientSecret
    Azure AD Client Secret
.PARAMETER ServerUrl
    URL du serveur MCP Weather sécurisé
.PARAMETER TestEndpoint
    Teste l'endpoint avec le token obtenu
.EXAMPLE
    .\azure-get-token.ps1 -TenantId "your-tenant-id" -ClientId "your-client-id" -ClientSecret "your-secret"
    .\azure-get-token.ps1 -TenantId "your-tenant-id" -ClientId "your-client-id" -ClientSecret "your-secret" -ServerUrl "http://your-server.com:8000" -TestEndpoint
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$true)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$true)]
    [string]$ClientSecret,
    
    [Parameter(Mandatory=$false)]
    [string]$ServerUrl,
    
    [Parameter(Mandatory=$false)]
    [switch]$TestEndpoint
)

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Step {
    param([string]$Message)
    Write-ColorOutput "🔄 $Message" "Cyan"
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "✅ $Message" "Green"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "❌ $Message" "Red"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "⚠️  $Message" "Yellow"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "ℹ️  $Message" "Blue"
}

# En-tête
Write-ColorOutput "🔑 Générateur de token Azure AD - MCP Weather" "Magenta"
Write-ColorOutput "=============================================" "Magenta"

# Configuration Azure AD
$tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$scope = "api://$ClientId/.default"  # Scope pour l'application personnalisée

Write-ColorOutput "`n📋 Configuration:" "Yellow"
Write-ColorOutput "  • Tenant ID: $TenantId" "White"
Write-ColorOutput "  • Client ID: $ClientId" "White"
Write-ColorOutput "  • Token URL: $tokenUrl" "White"
if ($ServerUrl) {
    Write-ColorOutput "  • Server URL: $ServerUrl" "White"
}

# Étape 1: Obtenir le token Azure AD
Write-Step "Obtention du token Azure AD..."

try {
    # Préparer les données pour la requête
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $scope
        grant_type    = "client_credentials"
    }
    
    Write-Info "Tentative avec scope: $scope"
    
    # Faire la requête pour obtenir le token
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
    } catch {
        Write-Warning "Échec avec le scope personnalisé, tentative avec scope générique..."
        
        # Essayer avec un scope plus générique
        $body.scope = "https://graph.microsoft.com/.default"
        Write-Info "Tentative avec scope: $($body.scope)"
        $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
    }
    
    if ($response.access_token) {
        Write-Success "Token Azure AD obtenu avec succès"
        
        # Décoder le token pour afficher les informations
        $tokenParts = $response.access_token.Split('.')
        
        # Fonction pour corriger le padding Base64
        function Fix-Base64Padding {
            param([string]$base64String)
            $padding = 4 - ($base64String.Length % 4)
            if ($padding -ne 4) {
                $base64String += "=" * $padding
            }
            return $base64String
        }
        
        $headerB64 = Fix-Base64Padding $tokenParts[0]
        $payloadB64 = Fix-Base64Padding $tokenParts[1]
        
        $header = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($headerB64))
        $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payloadB64))
        
        $headerObj = $header | ConvertFrom-Json
        $payloadObj = $payload | ConvertFrom-Json
        
        Write-ColorOutput "`n🎫 Informations du token:" "Green"
        Write-ColorOutput "=========================" "Green"
        Write-ColorOutput "  • Type: $($response.token_type)" "White"
        Write-ColorOutput "  • Expire dans: $($response.expires_in) secondes" "White"
        Write-ColorOutput "  • Algorithme: $($headerObj.alg)" "White"
        Write-ColorOutput "  • Audience: $($payloadObj.aud)" "White"
        Write-ColorOutput "  • Issuer: $($payloadObj.iss)" "White"
        Write-ColorOutput "  • App ID: $($payloadObj.appid)" "White"
        
        # Calculer l'expiration
        $expirationTime = [DateTimeOffset]::FromUnixTimeSeconds($payloadObj.exp).ToLocalTime()
        Write-ColorOutput "  • Expire le: $expirationTime" "White"
        
        # Afficher le token (tronqué pour la sécurité)
        $truncatedToken = $response.access_token.Substring(0, 50) + "..." + $response.access_token.Substring($response.access_token.Length - 10)
        Write-ColorOutput "`n🔐 Token (tronqué):" "Blue"
        Write-ColorOutput $truncatedToken "Gray"
        
        # Sauvegarder le token complet dans un fichier temporaire
        $tokenFile = "azure_token.txt"
        $response.access_token | Out-File -FilePath $tokenFile -Encoding UTF8
        Write-Info "Token complet sauvegardé dans: $tokenFile"
        
        # Copier le token dans le presse-papiers si possible
        try {
            $response.access_token | Set-Clipboard
            Write-Success "Token copié dans le presse-papiers"
        } catch {
            Write-Warning "Impossible de copier dans le presse-papiers"
        }
        
    } else {
        Write-Error "Impossible d'obtenir le token Azure AD"
        Write-Error "Réponse: $($response | ConvertTo-Json)"
        exit 1
    }
    
} catch {
    Write-Error "Erreur lors de l'obtention du token: $_"
    Write-Error "Vérifiez vos identifiants Azure AD"
    exit 1
}

# Étape 2: Tester l'endpoint si demandé
if ($TestEndpoint -and $ServerUrl) {
    Write-Step "Test de l'authentification sur le serveur..."
    
    try {
        # Test sans authentification
        Write-Info "Test sans authentification (devrait échouer)..."
        try {
            $responseNoAuth = Invoke-WebRequest -Uri $ServerUrl -Method GET -TimeoutSec 10
            Write-Warning "⚠️  Le serveur répond sans authentification"
            Write-ColorOutput "Status: $($responseNoAuth.StatusCode)" "Yellow"
        } catch {
            Write-Success "✅ Le serveur requiert bien une authentification"
            Write-ColorOutput "Erreur attendue: $($_.Exception.Message)" "Gray"
        }
        
        # Test avec authentification
        Write-Info "Test avec authentification..."
        $headers = @{
            "Authorization" = "Bearer $($response.access_token)"
            "Content-Type" = "application/json"
        }
        
        try {
            $responseAuth = Invoke-WebRequest -Uri $ServerUrl -Method GET -Headers $headers -TimeoutSec 10
            Write-Success "✅ Authentification réussie!"
            Write-ColorOutput "Status: $($responseAuth.StatusCode)" "Green"
            Write-ColorOutput "Response: $($responseAuth.Content.Substring(0, [Math]::Min(200, $responseAuth.Content.Length)))..." "Gray"
        } catch {
            Write-Warning "⚠️  Erreur avec authentification: $($_.Exception.Message)"
            
            # Analyser l'erreur
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode
                Write-ColorOutput "Status Code: $statusCode" "Yellow"
                
                if ($statusCode -eq 401) {
                    Write-Info "Le token pourrait ne pas être valide pour cette application"
                } elseif ($statusCode -eq 403) {
                    Write-Info "Le token est valide mais l'accès est refusé (vérifiez les rôles)"
                }
            }
        }
        
    } catch {
        Write-Error "Erreur lors du test: $_"
    }
}

# Étape 3: Instructions d'utilisation
Write-ColorOutput "`n📚 Instructions d'utilisation:" "Blue"
Write-ColorOutput "==============================" "Blue"
Write-ColorOutput "1. Utiliser avec curl:" "White"
Write-ColorOutput "   curl -H 'Authorization: Bearer YOUR_TOKEN' $ServerUrl" "Gray"
Write-ColorOutput ""
Write-ColorOutput "2. Utiliser avec PowerShell:" "White"
Write-ColorOutput "   `$headers = @{'Authorization' = 'Bearer YOUR_TOKEN'}" "Gray"
Write-ColorOutput "   Invoke-RestMethod -Uri '$ServerUrl' -Headers `$headers" "Gray"
Write-ColorOutput ""
Write-ColorOutput "3. Utiliser le token depuis le fichier:" "White"
Write-ColorOutput "   `$token = Get-Content 'azure_token.txt'" "Gray"
Write-ColorOutput ""
Write-ColorOutput "4. Tester l'API MCP Weather:" "White"
Write-ColorOutput "   curl -H 'Authorization: Bearer YOUR_TOKEN' -H 'Content-Type: application/json' \\" "Gray"
Write-ColorOutput "        -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_weather\",\"arguments\":{\"city\":\"Paris\"}}}' \\" "Gray"
Write-ColorOutput "        $ServerUrl" "Gray"

Write-ColorOutput "`n🔧 Dépannage:" "Yellow"
Write-ColorOutput "=============" "Yellow"
Write-ColorOutput "• Si le token ne fonctionne pas:" "White"
Write-ColorOutput "  - Vérifiez que l'application Azure AD a les bonnes permissions" "Gray"
Write-ColorOutput "  - Vérifiez que le serveur utilise le même Tenant ID" "Gray"
Write-ColorOutput "  - Vérifiez que le token n'est pas expiré" "Gray"
Write-ColorOutput ""
Write-ColorOutput "• Pour renouveler le token:" "White"
Write-ColorOutput "  - Relancez ce script" "Gray"
Write-ColorOutput "  - Le token est valide pendant $($response.expires_in) secondes" "Gray"

Write-ColorOutput "`n💡 Conseils de sécurité:" "Yellow"
Write-ColorOutput "========================" "Yellow"
Write-ColorOutput "• Ne partagez jamais votre token d'accès" "Red"
Write-ColorOutput "• Supprimez le fichier azure_token.txt après utilisation" "Red"
Write-ColorOutput "• Utilisez HTTPS en production" "Red"
Write-ColorOutput "• Configurez des rôles appropriés dans Azure AD" "Red"

Write-ColorOutput "`n🎉 Token généré avec succès!" "Green"
if ($TestEndpoint -and $ServerUrl) {
    Write-ColorOutput "Test d'authentification terminé!" "Green"
} else {
    Write-ColorOutput "Utilisez -TestEndpoint -ServerUrl pour tester automatiquement" "Blue"
} 