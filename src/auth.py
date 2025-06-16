"""
Module d'authentification Azure AD (Entra ID) pour le serveur MCP
Conforme RGPD avec gestion des logs anonymisés
"""
import os
import jwt
import httpx
import logging
from datetime import datetime, timezone
from typing import Optional, Dict, Any
from fastapi import HTTPException, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import hashlib

# Configuration du logging conforme RGPD
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration Azure AD
AZURE_AD_TENANT_ID = os.getenv("AZURE_AD_TENANT_ID")
AZURE_AD_CLIENT_ID = os.getenv("AZURE_AD_CLIENT_ID")
AZURE_AD_CLIENT_SECRET = os.getenv("AZURE_AD_CLIENT_SECRET")

# URLs Azure AD
AZURE_AD_AUTHORITY = f"https://login.microsoftonline.com/{AZURE_AD_TENANT_ID}"
AZURE_AD_JWKS_URL = f"{AZURE_AD_AUTHORITY}/discovery/v2.0/keys"
AZURE_AD_TOKEN_URL = f"{AZURE_AD_AUTHORITY}/oauth2/v2.0/token"

# Configuration de sécurité
security = HTTPBearer()


class GDPRLogger:
    """Logger conforme RGPD - anonymise les données personnelles"""

    @staticmethod
    def anonymize_user_id(user_id: str) -> str:
        """Anonymise l'ID utilisateur pour les logs"""
        return hashlib.sha256(user_id.encode()).hexdigest()[:8]

    @staticmethod
    def log_access(user_id: str, endpoint: str, success: bool, ip_address: str = None):
        """Log d'accès conforme RGPD"""
        anonymized_user = GDPRLogger.anonymize_user_id(user_id)
        anonymized_ip = hashlib.sha256(ip_address.encode()).hexdigest()[
            :8] if ip_address else "unknown"

        logger.info(
            f"ACCESS: user={anonymized_user}, endpoint={endpoint}, success={success}, ip_hash={anonymized_ip}")

    @staticmethod
    def log_data_processing(user_id: str, data_type: str, operation: str):
        """Log de traitement de données conforme RGPD"""
        anonymized_user = GDPRLogger.anonymize_user_id(user_id)
        logger.info(
            f"DATA_PROCESSING: user={anonymized_user}, type={data_type}, operation={operation}")


class AzureADAuth:
    """Gestionnaire d'authentification Azure AD"""

    def __init__(self):
        self.jwks_cache = {}
        self.jwks_cache_time = None

        # Vérification de la configuration
        if not all([AZURE_AD_TENANT_ID, AZURE_AD_CLIENT_ID]):
            raise ValueError(
                "Configuration Azure AD incomplète. Vérifiez les variables d'environnement.")

    async def get_jwks(self) -> Dict[str, Any]:
        """Récupère les clés publiques Azure AD (avec cache)"""
        now = datetime.now(timezone.utc)

        # Cache de 1 heure
        if (self.jwks_cache_time and
            (now - self.jwks_cache_time).total_seconds() < 3600 and
                self.jwks_cache):
            return self.jwks_cache

        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(AZURE_AD_JWKS_URL)
                response.raise_for_status()

                self.jwks_cache = response.json()
                self.jwks_cache_time = now
                return self.jwks_cache

        except Exception as e:
            logger.error(f"Erreur lors de la récupération des clés JWKS: {e}")
            raise HTTPException(
                status_code=503, detail="Service d'authentification indisponible")

    def get_public_key(self, token_header: Dict[str, Any], jwks: Dict[str, Any]) -> str:
        """Extrait la clé publique correspondant au token"""
        kid = token_header.get("kid")
        if not kid:
            raise HTTPException(
                status_code=401, detail="Token invalide: kid manquant")

        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                # Construction de la clé publique
                from cryptography.hazmat.primitives import serialization
                from cryptography.hazmat.primitives.asymmetric import rsa
                import base64

                n = base64.urlsafe_b64decode(key["n"] + "==")
                e = base64.urlsafe_b64decode(key["e"] + "==")

                public_numbers = rsa.RSAPublicNumbers(
                    int.from_bytes(e, byteorder="big"),
                    int.from_bytes(n, byteorder="big")
                )
                public_key = public_numbers.public_key()

                return public_key.public_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PublicFormat.SubjectPublicKeyInfo
                )

        raise HTTPException(status_code=401, detail="Clé publique non trouvée")

    async def validate_token(self, token: str, request: Request) -> Dict[str, Any]:
        """Valide un token Azure AD"""
        try:
            # Décodage du header sans vérification
            unverified_header = jwt.get_unverified_header(token)

            # Récupération des clés publiques
            jwks = await self.get_jwks()

            # Récupération de la clé publique
            public_key = self.get_public_key(unverified_header, jwks)

            # Validation du token
            payload = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                audience=AZURE_AD_CLIENT_ID,
                issuer=f"https://login.microsoftonline.com/{AZURE_AD_TENANT_ID}/v2.0"
            )

            # Vérification de l'expiration
            now = datetime.now(timezone.utc).timestamp()
            if payload.get("exp", 0) < now:
                raise HTTPException(status_code=401, detail="Token expiré")

            # Log d'accès conforme RGPD
            user_id = payload.get("sub", "unknown")
            client_ip = request.client.host if request.client else "unknown"
            GDPRLogger.log_access(user_id, request.url.path, True, client_ip)

            return payload

        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=401, detail="Token expiré")
        except jwt.InvalidTokenError as e:
            logger.warning(f"Token invalide: {e}")
            raise HTTPException(status_code=401, detail="Token invalide")
        except Exception as e:
            logger.error(f"Erreur de validation du token: {e}")
            raise HTTPException(
                status_code=401, detail="Erreur d'authentification")


# Instance globale
azure_auth = AzureADAuth()


async def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> Dict[str, Any]:
    """Dependency pour récupérer l'utilisateur actuel"""
    if not credentials:
        raise HTTPException(
            status_code=401, detail="Token d'authentification requis")

    return await azure_auth.validate_token(credentials.credentials, request)


def require_role(required_role: str):
    """Decorator pour vérifier les rôles utilisateur"""
    def role_checker(user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        user_roles = user.get("roles", [])
        if required_role not in user_roles and "admin" not in user_roles:
            raise HTTPException(
                status_code=403,
                detail=f"Rôle requis: {required_role}"
            )
        return user
    return role_checker


class GDPRCompliance:
    """Gestionnaire de conformité RGPD"""

    @staticmethod
    def get_user_data_summary(user_id: str) -> Dict[str, Any]:
        """Retourne un résumé des données utilisateur (droit d'accès RGPD)"""
        return {
            "user_id": user_id,
            "data_collected": [
                "Logs d'accès anonymisés",
                "Historique des requêtes météo",
                "Timestamps d'utilisation"
            ],
            "data_retention": "30 jours pour les logs, 7 jours pour les données météo",
            "data_purpose": "Fourniture du service météo MCP",
            "data_sharing": "Aucun partage avec des tiers",
            "user_rights": [
                "Droit d'accès",
                "Droit de rectification",
                "Droit à l'effacement",
                "Droit à la portabilité"
            ]
        }

    @staticmethod
    async def delete_user_data(user_id: str) -> bool:
        """Supprime toutes les données utilisateur (droit à l'oubli RGPD)"""
        try:
            # Ici, vous implémenteriez la suppression réelle des données
            # Pour l'exemple, on log l'action
            GDPRLogger.log_data_processing(
                user_id, "all_user_data", "deletion")

            # Dans un vrai système, vous supprimeriez :
            # - Les logs contenant l'utilisateur
            # - Les données en cache
            # - Les préférences utilisateur
            # - etc.

            logger.info(
                f"Données utilisateur supprimées conformément au RGPD: {GDPRLogger.anonymize_user_id(user_id)}")
            return True

        except Exception as e:
            logger.error(
                f"Erreur lors de la suppression des données utilisateur: {e}")
            return False


# Instance de conformité RGPD
gdpr_compliance = GDPRCompliance()
