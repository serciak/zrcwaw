import os
import time
import requests
import urllib3
from jose import jwk, jwt
from jose.exceptions import JWTError
from jose.utils import base64url_decode
from fastapi import HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Dict, Optional

# Wyłącz ostrzeżenia o niezweryfikowanym SSL (dla self-signed certs)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

security = HTTPBearer()

# OIDC / Keycloak
OIDC_ISSUER_URL = os.getenv("OIDC_ISSUER_URL")  # np. https://<alb-dns>/realms/<realm>
OIDC_ISSUER_URL_EXTERNAL = os.getenv("OIDC_ISSUER_URL_EXTERNAL")  # zewnętrzny issuer (dla tokenów z frontendu)
OIDC_AUDIENCE = os.getenv("OIDC_AUDIENCE")  # client_id API (zalecane) albo SPA (fallback)
OIDC_JWKS_URL = os.getenv("OIDC_JWKS_URL")  # opcjonalnie: override
SSL_VERIFY = os.getenv("SSL_VERIFY", "true").lower() not in ("false", "0", "no")

if not OIDC_JWKS_URL and OIDC_ISSUER_URL:
    OIDC_JWKS_URL = f"{OIDC_ISSUER_URL.rstrip('/')}/protocol/openid-connect/certs"

jwks_cache: Optional[Dict] = None
jwks_cache_time: float = 0
JWKS_CACHE_DURATION = 3600


def _require(value: Optional[str], name: str) -> str:
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def get_jwks(force_refresh: bool = False) -> Dict:
    global jwks_cache, jwks_cache_time

    current_time = time.time()

    if not force_refresh and jwks_cache and (current_time - jwks_cache_time) < JWKS_CACHE_DURATION:
        return jwks_cache

    jwks_url = _require(OIDC_JWKS_URL, "OIDC_JWKS_URL (or set OIDC_ISSUER_URL)")
    response = requests.get(jwks_url, timeout=10, verify=SSL_VERIFY)
    response.raise_for_status()

    jwks_cache = response.json()
    jwks_cache_time = current_time
    return jwks_cache


def _select_key(jwks: Dict, kid: str) -> Optional[Dict]:
    for jwk_key in jwks.get("keys", []):
        if jwk_key.get("kid") == kid:
            return jwk_key
    return None


def verify_token(token: str) -> Dict:
    """Weryfikuje JWT (access token) wydany przez Keycloak/OIDC.

    Akceptuje warianty aud w Keycloak:
    - Standardowe `aud`
    - Lub `azp` (authorized party) przy tokenach, gdzie aud nie zawiera client_id.
    """
    try:
        issuer = _require(OIDC_ISSUER_URL, "OIDC_ISSUER_URL")

        headers = jwt.get_unverified_headers(token)
        kid = headers.get("kid")
        if not kid:
            raise HTTPException(status_code=401, detail="Invalid token header (missing kid)")

        jwks = get_jwks()
        key = _select_key(jwks, kid)

        # Obsłuż rotację kluczy: odśwież cache i spróbuj raz jeszcze
        if not key:
            jwks = get_jwks(force_refresh=True)
            key = _select_key(jwks, kid)

        if not key:
            raise HTTPException(status_code=401, detail="Public key not found in JWKs")

        public_key = jwk.construct(key)
        message, encoded_signature = token.rsplit('.', 1)
        decoded_signature = base64url_decode(encoded_signature.encode())

        if not public_key.verify(message.encode(), decoded_signature):
            raise HTTPException(status_code=401, detail="Invalid token signature")

        claims = jwt.get_unverified_claims(token)

        # exp
        exp = claims.get("exp")
        if not exp or time.time() > exp:
            raise HTTPException(status_code=401, detail="Token has expired")

        # iss - akceptuj wewnętrzny lub zewnętrzny issuer
        token_issuer = claims.get("iss")
        valid_issuers = [issuer]
        if OIDC_ISSUER_URL_EXTERNAL:
            valid_issuers.append(OIDC_ISSUER_URL_EXTERNAL)

        if token_issuer not in valid_issuers:
            raise HTTPException(status_code=401, detail="Invalid token issuer")

        # aud / azp
        if OIDC_AUDIENCE:
            aud = claims.get("aud")
            azp = claims.get("azp")
            aud_ok = False
            if isinstance(aud, str):
                aud_ok = (aud == OIDC_AUDIENCE)
            elif isinstance(aud, list):
                aud_ok = (OIDC_AUDIENCE in aud)

            # fallback na azp (często przy SPA)
            if not aud_ok and azp:
                aud_ok = (azp == OIDC_AUDIENCE)

            if not aud_ok:
                raise HTTPException(status_code=401, detail="Invalid token audience")

        return claims

    except requests.RequestException as e:
        raise HTTPException(status_code=503, detail=f"OIDC JWKS unavailable: {str(e)}")
    except JWTError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Token verification failed: {str(e)}")


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Security(security),
) -> Dict:
    token = credentials.credentials
    return verify_token(token)