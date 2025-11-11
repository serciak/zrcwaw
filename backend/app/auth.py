import os
import time
import requests
from jose import jwk, jwt
from jose.utils import base64url_decode
from fastapi import HTTPException, Security, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Dict, Optional

security = HTTPBearer()

COGNITO_REGION = os.getenv("COGNITO_REGION", "us-east-1")
COGNITO_USER_POOL_ID = os.getenv("COGNITO_USER_POOL_ID")
COGNITO_USER_POOL_WEB_CLIENT_ID = os.getenv("COGNITO_USER_POOL_WEB_CLIENT_ID")

COGNITO_JWKS_URL = f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{COGNITO_USER_POOL_ID}/.well-known/jwks.json"

jwks_cache: Optional[Dict] = None
jwks_cache_time: float = 0
JWKS_CACHE_DURATION = 3600


def get_jwks() -> Dict:
    """Fetch and cache JWKs from Cognito"""
    global jwks_cache, jwks_cache_time

    current_time = time.time()

    # Return cached JWKs if still valid
    if jwks_cache and (current_time - jwks_cache_time) < JWKS_CACHE_DURATION:
        return jwks_cache

    # Fetch new JWKs
    response = requests.get(COGNITO_JWKS_URL)
    jwks_cache = response.json()
    jwks_cache_time = current_time

    return jwks_cache


def verify_token(token: str) -> Dict:
    """
    Verify a Cognito JWT token
    Returns the decoded token payload if valid
    Raises HTTPException if invalid
    """
    try:
        # Get the kid from the token header
        headers = jwt.get_unverified_headers(token)
        kid = headers['kid']

        # Get the JWKs
        jwks = get_jwks()

        # Find the correct key
        key = None
        for jwk_key in jwks['keys']:
            if jwk_key['kid'] == kid:
                key = jwk_key
                break

        if not key:
            raise HTTPException(status_code=401, detail="Public key not found in JWKs")

        # Construct the public key
        public_key = jwk.construct(key)

        # Get the message and signature from token
        message, encoded_signature = token.rsplit('.', 1)
        decoded_signature = base64url_decode(encoded_signature.encode())

        # Verify signature
        if not public_key.verify(message.encode(), decoded_signature):
            raise HTTPException(status_code=401, detail="Invalid token signature")

        # Decode and verify claims
        claims = jwt.get_unverified_claims(token)

        # Verify token expiration
        if time.time() > claims['exp']:
            raise HTTPException(status_code=401, detail="Token has expired")

        # Verify token use
        token_use = claims.get('token_use')
        if token_use not in ['access', 'id']:
            raise HTTPException(status_code=401, detail="Invalid token use")

        # Verify audience/client_id based on token type
        if token_use == 'id':
            # ID tokens use 'aud' claim
            if claims.get('aud') != COGNITO_USER_POOL_WEB_CLIENT_ID:
                raise HTTPException(status_code=401, detail="Invalid token audience")
        elif token_use == 'access':
            # Access tokens use 'client_id' claim
            if claims.get('client_id') != COGNITO_USER_POOL_WEB_CLIENT_ID:
                raise HTTPException(status_code=401, detail="Invalid token client_id")

        return claims

    except jwt.JWTError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")
    except KeyError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token structure: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Token verification failed: {str(e)}")


async def get_current_user(
        credentials: HTTPAuthorizationCredentials = Security(security)
) -> Dict:
    """
    FastAPI dependency to get current authenticated user
    Usage: user = Depends(get_current_user)
    """
    token = credentials.credentials
    return verify_token(token)