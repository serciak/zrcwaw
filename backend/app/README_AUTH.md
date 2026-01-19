# Dokumentacja modułu `auth.py` - Szczegółowy opis kodu

Ten dokument zawiera szczegółowe wyjaśnienie każdej linii i każdego elementu kodu w pliku `auth.py`. Plik ten odpowiada za uwierzytelnianie użytkowników za pomocą tokenów JWT wydawanych przez serwer OIDC (OpenID Connect), w tym przypadku Keycloak.

---

## Spis treści

1. [Importy](#1-importy)
2. [Wyłączenie ostrzeżeń SSL](#2-wyłączenie-ostrzeżeń-ssl)
3. [Konfiguracja HTTPBearer](#3-konfiguracja-httpbearer)
4. [Zmienne konfiguracyjne (środowiskowe)](#4-zmienne-konfiguracyjne-środowiskowe)
5. [Automatyczne ustawienie JWKS URL](#5-automatyczne-ustawienie-jwks-url)
6. [Cache JWKS](#6-cache-jwks)
7. [Funkcja `_require`](#7-funkcja-_require)
8. [Funkcja `get_jwks`](#8-funkcja-get_jwks)
9. [Funkcja `_select_key`](#9-funkcja-_select_key)
10. [Funkcja `verify_token`](#10-funkcja-verify_token)
11. [Funkcja `get_current_user`](#11-funkcja-get_current_user)

---

## 1. Importy

```python
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
```

### Szczegółowy opis każdego importu:

| Import | Opis |
|--------|------|
| `import os` | Moduł standardowy Pythona do interakcji z systemem operacyjnym. Używany tutaj do odczytu zmiennych środowiskowych za pomocą `os.getenv()`. |
| `import time` | Moduł standardowy Pythona do operacji związanych z czasem. Używany do: (1) sprawdzania czy cache JWKS jest jeszcze ważny, (2) porównywania aktualnego czasu z czasem wygaśnięcia tokenu (`exp`). |
| `import requests` | Zewnętrzna biblioteka HTTP do wykonywania żądań sieciowych. Używana do pobierania kluczy JWKS z serwera Keycloak. |
| `import urllib3` | Biblioteka HTTP niskiego poziomu (używana wewnętrznie przez `requests`). Tutaj importowana tylko po to, by wyłączyć ostrzeżenia o niezweryfikowanych certyfikatach SSL. |
| `from jose import jwk, jwt` | Biblioteka `python-jose` do obsługi JWT (JSON Web Tokens). `jwk` - moduł do pracy z kluczami JWK (JSON Web Keys). `jwt` - moduł do parsowania i weryfikacji tokenów JWT. |
| `from jose.exceptions import JWTError` | Klasa wyjątku wyrzucanego przez bibliotekę `jose` w przypadku problemów z tokenem JWT (np. nieprawidłowy format, błędna sygnatura). |
| `from jose.utils import base64url_decode` | Funkcja do dekodowania danych zakodowanych w formacie Base64URL. Używana do dekodowania sygnatury tokenu JWT. |
| `from fastapi import HTTPException, Security` | `HTTPException` - klasa wyjątku FastAPI do zwracania odpowiedzi błędów HTTP z kodem statusu i szczegółami. `Security` - dekorator/funkcja FastAPI do wstrzykiwania zależności bezpieczeństwa. |
| `from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials` | `HTTPBearer` - klasa implementująca schemat uwierzytelniania Bearer (oczekuje nagłówka `Authorization: Bearer <token>`). `HTTPAuthorizationCredentials` - obiekt zawierający dane uwierzytelniające (scheme i credentials). |
| `from typing import Dict, Optional` | Typy do adnotacji typów w Pythonie. `Dict` - słownik, `Optional[X]` - wartość typu X lub None. |

---

## 2. Wyłączenie ostrzeżeń SSL

```python
# Wyłącz ostrzeżenia o niezweryfikowanym SSL (dla self-signed certs)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
```

### Szczegółowy opis:

- **Co to robi:** Wyłącza ostrzeżenia biblioteki `urllib3` o niezweryfikowanych certyfikatach SSL.
- **Dlaczego to jest potrzebne:** Gdy aplikacja łączy się z serwerem Keycloak używającym samopodpisanego certyfikatu (self-signed certificate), biblioteka `requests` (która używa `urllib3` pod spodem) wyświetla ostrzeżenia typu `InsecureRequestWarning` przy każdym żądaniu.
- **`urllib3.exceptions.InsecureRequestWarning`:** Jest to konkretny typ ostrzeżenia, który jest wyświetlany gdy wykonujesz żądanie HTTPS z `verify=False`.
- **Uwaga bezpieczeństwa:** To rozwiązanie jest akceptowalne w środowiskach deweloperskich lub wewnętrznych sieciach. W produkcji zaleca się używanie prawidłowych certyfikatów SSL.

---

## 3. Konfiguracja HTTPBearer

```python
security = HTTPBearer()
```

### Szczegółowy opis:

- **Co to robi:** Tworzy instancję klasy `HTTPBearer`, która jest używana jako schemat bezpieczeństwa FastAPI.
- **Jak działa HTTPBearer:**
  1. Automatycznie sprawdza nagłówek `Authorization` w przychodzących żądaniach HTTP
  2. Oczekuje formatu: `Authorization: Bearer <token>`
  3. Jeśli nagłówek jest nieobecny lub nieprawidłowy, automatycznie zwraca błąd 401/403
  4. Jeśli nagłówek jest prawidłowy, wyodrębnia token i przekazuje go jako `HTTPAuthorizationCredentials`
- **Użycie w OpenAPI/Swagger:** Ta instancja automatycznie generuje dokumentację bezpieczeństwa w schemacie OpenAPI (widoczną w Swagger UI).

---

## 4. Zmienne konfiguracyjne (środowiskowe)

```python
# OIDC / Keycloak
OIDC_ISSUER_URL = os.getenv("OIDC_ISSUER_URL")  # np. https://<alb-dns>/realms/<realm>
OIDC_ISSUER_URL_EXTERNAL = os.getenv("OIDC_ISSUER_URL_EXTERNAL")  # zewnętrzny issuer (dla tokenów z frontendu)
OIDC_AUDIENCE = os.getenv("OIDC_AUDIENCE")  # client_id API (zalecane) albo SPA (fallback)
OIDC_JWKS_URL = os.getenv("OIDC_JWKS_URL")  # opcjonalnie: override
SSL_VERIFY = os.getenv("SSL_VERIFY", "true").lower() not in ("false", "0", "no")
```

### Szczegółowy opis każdej zmiennej:

#### `OIDC_ISSUER_URL`
```python
OIDC_ISSUER_URL = os.getenv("OIDC_ISSUER_URL")
```
- **Co to jest:** URL wydawcy tokenów (issuer) w standardzie OIDC.
- **Format przykładowy:** `https://keycloak.example.com/realms/myrealm`
- **Do czego służy:** 
  1. Do walidacji claim `iss` w tokenie (sprawdzenie czy token pochodzi od zaufanego wydawcy)
  2. Do automatycznego wygenerowania URL-a JWKS (jeśli `OIDC_JWKS_URL` nie jest ustawiony)
- **`os.getenv("OIDC_ISSUER_URL")`:** Pobiera wartość zmiennej środowiskowej. Jeśli zmienna nie istnieje, zwraca `None`.

#### `OIDC_ISSUER_URL_EXTERNAL`
```python
OIDC_ISSUER_URL_EXTERNAL = os.getenv("OIDC_ISSUER_URL_EXTERNAL")
```
- **Co to jest:** Alternatywny URL wydawcy dla tokenów z frontendu.
- **Dlaczego to jest potrzebne:** W niektórych architekturach (np. z load balancerem) frontend może widzieć Keycloak pod innym adresem niż backend. Token wydany przez Keycloak będzie miał `iss` odpowiadający temu, jak frontend widzi Keycloak. Dlatego backend musi akceptować oba warianty.
- **Przykład:** 
  - Backend widzi Keycloak jako: `http://keycloak:8080/realms/myrealm`
  - Frontend widzi Keycloak jako: `https://auth.example.com/realms/myrealm`

#### `OIDC_AUDIENCE`
```python
OIDC_AUDIENCE = os.getenv("OIDC_AUDIENCE")
```
- **Co to jest:** Identyfikator odbiorcy (audience) dla którego token został wydany.
- **Co to oznacza w praktyce:** To zazwyczaj `client_id` aplikacji zarejestrowanej w Keycloak.
- **Do czego służy:** Do walidacji claim `aud` lub `azp` w tokenie - upewnia się, że token został wydany dla tej konkretnej aplikacji, a nie dla innej.
- **Opcjonalność:** Jeśli ta zmienna nie jest ustawiona (jest `None`), walidacja audience jest pomijana.

#### `OIDC_JWKS_URL`
```python
OIDC_JWKS_URL = os.getenv("OIDC_JWKS_URL")
```
- **Co to jest:** URL do endpointu JWKS (JSON Web Key Set).
- **Co to jest JWKS:** Zestaw kluczy publicznych używanych do weryfikacji sygnatur tokenów JWT.
- **Kiedy używać:** Gdy chcesz nadpisać automatycznie wygenerowany URL lub gdy endpoint JWKS jest pod niestandardowym adresem.
- **Format przykładowy:** `https://keycloak.example.com/realms/myrealm/protocol/openid-connect/certs`

#### `SSL_VERIFY`
```python
SSL_VERIFY = os.getenv("SSL_VERIFY", "true").lower() not in ("false", "0", "no")
```
- **Co to robi:** Określa czy weryfikować certyfikaty SSL przy połączeniach z serwerem JWKS.
- **Analiza wyrażenia krok po kroku:**
  1. `os.getenv("SSL_VERIFY", "true")` - pobiera zmienną środowiskową, domyślnie `"true"`
  2. `.lower()` - konwertuje na małe litery (np. `"TRUE"` → `"true"`, `"False"` → `"false"`)
  3. `not in ("false", "0", "no")` - sprawdza czy wartość NIE jest jedną z wartości wyłączających
  4. Wynik: `True` jeśli SSL ma być weryfikowany, `False` jeśli nie
- **Przykłady:**
  - `SSL_VERIFY=true` → `True` (weryfikuj)
  - `SSL_VERIFY=false` → `False` (nie weryfikuj)
  - `SSL_VERIFY=0` → `False` (nie weryfikuj)
  - `SSL_VERIFY=no` → `False` (nie weryfikuj)
  - `SSL_VERIFY=yes` → `True` (weryfikuj)
  - Brak zmiennej → `True` (domyślnie weryfikuj)

---

## 5. Automatyczne ustawienie JWKS URL

```python
if not OIDC_JWKS_URL and OIDC_ISSUER_URL:
    OIDC_JWKS_URL = f"{OIDC_ISSUER_URL.rstrip('/')}/protocol/openid-connect/certs"
```

### Szczegółowy opis:

- **Warunek:** Wykonuje się tylko jeśli:
  - `OIDC_JWKS_URL` nie jest ustawiony (jest `None` lub pusty string)
  - ORAZ `OIDC_ISSUER_URL` jest ustawiony
- **Co robi:**
  1. `OIDC_ISSUER_URL.rstrip('/')` - usuwa końcowy slash z URL-a (jeśli istnieje), aby uniknąć podwójnych slashy
  2. Dodaje standardową ścieżkę JWKS dla Keycloak: `/protocol/openid-connect/certs`
- **Przykład:**
  - Input: `OIDC_ISSUER_URL = "https://keycloak.example.com/realms/myrealm/"`
  - Output: `OIDC_JWKS_URL = "https://keycloak.example.com/realms/myrealm/protocol/openid-connect/certs"`
- **Dlaczego `/protocol/openid-connect/certs`:** Jest to standardowa ścieżka endpointu JWKS w Keycloak. Inne serwery OIDC mogą używać innej ścieżki.

---

## 6. Cache JWKS

```python
jwks_cache: Optional[Dict] = None
jwks_cache_time: float = 0
JWKS_CACHE_DURATION = 3600
```

### Szczegółowy opis:

#### `jwks_cache: Optional[Dict] = None`
- **Typ:** `Optional[Dict]` - słownik lub `None`
- **Wartość początkowa:** `None` (brak danych w cache)
- **Co przechowuje:** Odpowiedź JSON z endpointu JWKS zawierającą klucze publiczne
- **Struktura przykładowa:**
  ```json
  {
    "keys": [
      {
        "kid": "abc123",
        "kty": "RSA",
        "alg": "RS256",
        "use": "sig",
        "n": "...",
        "e": "AQAB"
      }
    ]
  }
  ```

#### `jwks_cache_time: float = 0`
- **Typ:** `float` - liczba zmiennoprzecinkowa
- **Wartość początkowa:** `0` (timestamp uniksowy - 1 stycznia 1970)
- **Co przechowuje:** Czas (jako Unix timestamp) ostatniego pobrania JWKS
- **Do czego służy:** Do obliczenia czy cache jest jeszcze ważny

#### `JWKS_CACHE_DURATION = 3600`
- **Typ:** `int` - liczba całkowita
- **Wartość:** `3600` sekund = 1 godzina
- **Co oznacza:** Cache JWKS jest ważny przez 1 godzinę od momentu pobrania
- **Dlaczego cachowanie:** 
  1. Zmniejsza liczbę żądań do serwera Keycloak
  2. Przyspiesza weryfikację tokenów
  3. Klucze JWKS zmieniają się rzadko (rotacja kluczy)

---

## 7. Funkcja `_require`

```python
def _require(value: Optional[str], name: str) -> str:
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value
```

### Szczegółowy opis:

#### Sygnatura funkcji:
- **`value: Optional[str]`** - wartość do sprawdzenia (może być stringiem lub `None`)
- **`name: str`** - nazwa zmiennej (używana w komunikacie błędu)
- **`-> str`** - funkcja zwraca string (nigdy `None`)

#### Logika:
1. **`if not value:`** - sprawdza czy wartość jest "falsy":
   - `None` → `True` (brak wartości)
   - `""` (pusty string) → `True` (pusty string traktowany jako brak wartości)
   - `"cokolwiek"` → `False` (wartość istnieje)

2. **`raise RuntimeError(...)`** - rzuca wyjątek typu `RuntimeError` z komunikatem informującym o brakującej zmiennej środowiskowej

3. **`return value`** - jeśli wartość istnieje, zwraca ją

#### Dlaczego `_` na początku nazwy:
- Konwencja Pythona oznaczająca "prywatną" funkcję (do użytku wewnętrznego modułu)
- Sygnalizuje innym programistom, że nie powinna być importowana/używana poza tym modułem

#### Przykłady użycia:
```python
_require(None, "OIDC_ISSUER_URL")  # RuntimeError: Missing required environment variable: OIDC_ISSUER_URL
_require("", "OIDC_ISSUER_URL")    # RuntimeError: Missing required environment variable: OIDC_ISSUER_URL
_require("https://...", "OIDC_ISSUER_URL")  # Zwraca: "https://..."
```

---

## 8. Funkcja `get_jwks`

```python
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
```

### Szczegółowy opis linia po linii:

#### Sygnatura:
```python
def get_jwks(force_refresh: bool = False) -> Dict:
```
- **`force_refresh: bool = False`** - parametr opcjonalny, domyślnie `False`. Jeśli `True`, wymusza pobranie świeżych danych JWKS nawet jeśli cache jest ważny.
- **`-> Dict`** - funkcja zwraca słownik z kluczami JWKS

#### Deklaracja zmiennych globalnych:
```python
global jwks_cache, jwks_cache_time
```
- Słowo kluczowe `global` pozwala na modyfikację zmiennych zdefiniowanych na poziomie modułu
- Bez tego słowa kluczowego, przypisanie do tych zmiennych stworzyłoby nowe zmienne lokalne

#### Pobranie aktualnego czasu:
```python
current_time = time.time()
```
- `time.time()` zwraca aktualny czas jako Unix timestamp (liczba sekund od 1 stycznia 1970 UTC)
- Przykład: `1705680000.123456`

#### Warunek sprawdzający cache:
```python
if not force_refresh and jwks_cache and (current_time - jwks_cache_time) < JWKS_CACHE_DURATION:
    return jwks_cache
```
Analiza warunku (wszystkie muszą być spełnione):
1. **`not force_refresh`** - nie wymuszono odświeżenia
2. **`jwks_cache`** - cache istnieje (nie jest `None`)
3. **`(current_time - jwks_cache_time) < JWKS_CACHE_DURATION`** - cache nie wygasł (różnica czasów < 3600 sekund)

Jeśli wszystkie warunki są spełnione, funkcja natychmiast zwraca dane z cache bez wykonywania żądania HTTP.

#### Pobieranie JWKS z serwera:
```python
jwks_url = _require(OIDC_JWKS_URL, "OIDC_JWKS_URL (or set OIDC_ISSUER_URL)")
```
- Używa funkcji `_require` do upewnienia się, że URL JWKS jest ustawiony
- Jeśli nie jest ustawiony, rzuca `RuntimeError` z pomocną wiadomością

```python
response = requests.get(jwks_url, timeout=10, verify=SSL_VERIFY)
```
- **`requests.get(jwks_url, ...)`** - wykonuje żądanie HTTP GET na podany URL
- **`timeout=10`** - limit czasu na odpowiedź to 10 sekund. Jeśli serwer nie odpowie w tym czasie, zostanie rzucony wyjątek `requests.Timeout`
- **`verify=SSL_VERIFY`** - określa czy weryfikować certyfikat SSL (wartość pochodzi ze zmiennej środowiskowej)

```python
response.raise_for_status()
```
- Sprawdza kod statusu HTTP odpowiedzi
- Jeśli status jest błędny (4xx lub 5xx), rzuca wyjątek `requests.HTTPError`
- Przykłady:
  - Status 200 → nic nie robi
  - Status 404 → rzuca `HTTPError: 404 Client Error: Not Found`
  - Status 500 → rzuca `HTTPError: 500 Server Error: Internal Server Error`

#### Aktualizacja cache:
```python
jwks_cache = response.json()
```
- `response.json()` parsuje odpowiedź jako JSON i zwraca słownik Pythona
- Wynik jest zapisywany do globalnej zmiennej `jwks_cache`

```python
jwks_cache_time = current_time
```
- Zapisuje czas pobrania JWKS do globalnej zmiennej (do późniejszego sprawdzania ważności cache)

```python
return jwks_cache
```
- Zwraca świeżo pobrane (lub zaktualizowane) dane JWKS

---

## 9. Funkcja `_select_key`

```python
def _select_key(jwks: Dict, kid: str) -> Optional[Dict]:
    for jwk_key in jwks.get("keys", []):
        if jwk_key.get("kid") == kid:
            return jwk_key
    return None
```

### Szczegółowy opis:

#### Sygnatura:
- **`jwks: Dict`** - słownik JWKS zawierający listę kluczy
- **`kid: str`** - Key ID (identyfikator klucza) do wyszukania
- **`-> Optional[Dict]`** - zwraca słownik z kluczem lub `None` jeśli nie znaleziono

#### Logika:
```python
for jwk_key in jwks.get("keys", []):
```
- **`jwks.get("keys", [])`** - pobiera listę kluczy z JWKS. Jeśli klucz "keys" nie istnieje, zwraca pustą listę `[]` (bezpieczne domyślne zachowanie)
- Iteruje przez wszystkie klucze w liście

```python
if jwk_key.get("kid") == kid:
    return jwk_key
```
- Dla każdego klucza sprawdza czy jego `kid` (Key ID) odpowiada szukanemu
- Jeśli tak, natychmiast zwraca ten klucz

```python
return None
```
- Jeśli żaden klucz nie pasuje, zwraca `None`

#### Co to jest `kid` (Key ID):
- Unikalny identyfikator klucza w zestawie JWKS
- Token JWT zawiera `kid` w nagłówku, wskazując który klucz został użyty do jego podpisania
- Przykład nagłówka JWT: `{"alg": "RS256", "typ": "JWT", "kid": "abc123"}`

---

## 10. Funkcja `verify_token`

```python
def verify_token(token: str) -> Dict:
    """Weryfikuje JWT (access token) wydany przez Keycloak/OIDC.

    Akceptuje warianty aud w Keycloak:
    - Standardowe `aud`
    - Lub `azp` (authorized party) przy tokenach, gdzie aud nie zawiera client_id.
    """
```

### Sygnatura i docstring:
- **`token: str`** - token JWT do weryfikacji (sam token, bez prefiksu "Bearer")
- **`-> Dict`** - zwraca claims (zawartość) tokenu jako słownik
- **Docstring:** Wyjaśnia, że funkcja weryfikuje tokeny JWT wydane przez Keycloak i obsługuje różne warianty claim `aud`/`azp`

### Blok try:
```python
try:
    issuer = _require(OIDC_ISSUER_URL, "OIDC_ISSUER_URL")
```
- Cały kod weryfikacji jest w bloku `try` do obsługi różnych wyjątków
- Pobiera i waliduje wymagany URL wydawcy

### Pobranie nagłówka tokenu:
```python
headers = jwt.get_unverified_headers(token)
kid = headers.get("kid")
if not kid:
    raise HTTPException(status_code=401, detail="Invalid token header (missing kid)")
```
- **`jwt.get_unverified_headers(token)`** - parsuje nagłówek JWT BEZ weryfikacji sygnatury
- Pobiera `kid` (Key ID) z nagłówka
- Jeśli `kid` brakuje, token jest nieprawidłowy (nie można ustalić którym kluczem był podpisany)

### Pobranie klucza publicznego:
```python
jwks = get_jwks()
key = _select_key(jwks, kid)

# Obsłuż rotację kluczy: odśwież cache i spróbuj raz jeszcze
if not key:
    jwks = get_jwks(force_refresh=True)
    key = _select_key(jwks, kid)

if not key:
    raise HTTPException(status_code=401, detail="Public key not found in JWKs")
```
1. Pobiera JWKS (z cache lub serwera)
2. Szuka klucza o danym `kid`
3. **Obsługa rotacji kluczy:** Jeśli klucz nie został znaleziony, może to oznaczać, że Keycloak dokonał rotacji kluczy. Wtedy:
   - Wymusza odświeżenie cache (`force_refresh=True`)
   - Próbuje ponownie znaleźć klucz
4. Jeśli nadal nie znaleziono klucza, token jest nieprawidłowy

### Weryfikacja sygnatury:
```python
public_key = jwk.construct(key)
message, encoded_signature = token.rsplit('.', 1)
decoded_signature = base64url_decode(encoded_signature.encode())

if not public_key.verify(message.encode(), decoded_signature):
    raise HTTPException(status_code=401, detail="Invalid token signature")
```

#### Analiza:
1. **`jwk.construct(key)`** - tworzy obiekt klucza kryptograficznego z danych JWK
2. **`token.rsplit('.', 1)`** - dzieli token JWT na dwie części:
   - Token JWT ma format: `header.payload.signature`
   - `rsplit('.', 1)` dzieli od prawej, maksymalnie na 2 części
   - `message` = `"header.payload"` (to co było podpisane)
   - `encoded_signature` = `"signature"` (zakodowana sygnatura)
3. **`base64url_decode(encoded_signature.encode())`** - dekoduje sygnaturę z Base64URL na bajty
4. **`public_key.verify(...)`** - weryfikuje czy sygnatura jest prawidłowa:
   - Bierze wiadomość (`header.payload`) i dekodowaną sygnaturę
   - Sprawdza czy sygnatura została wygenerowana kluczem prywatnym odpowiadającym kluczowi publicznemu
   - Zwraca `True` jeśli sygnatura jest prawidłowa

### Pobranie claims:
```python
claims = jwt.get_unverified_claims(token)
```
- Parsuje payload JWT i zwraca jako słownik
- "Unverified" bo sygnatura już została zweryfikowana ręcznie powyżej

### Walidacja czasu wygaśnięcia (exp):
```python
# exp
exp = claims.get("exp")
if not exp or time.time() > exp:
    raise HTTPException(status_code=401, detail="Token has expired")
```
- **`exp`** - claim określający kiedy token wygasa (Unix timestamp)
- Jeśli `exp` nie istnieje lub aktualny czas jest większy niż `exp`, token wygasł

### Walidacja wydawcy (iss):
```python
# iss - akceptuj wewnętrzny lub zewnętrzny issuer
token_issuer = claims.get("iss")
valid_issuers = [issuer]
if OIDC_ISSUER_URL_EXTERNAL:
    valid_issuers.append(OIDC_ISSUER_URL_EXTERNAL)

if token_issuer not in valid_issuers:
    raise HTTPException(status_code=401, detail="Invalid token issuer")
```
1. Pobiera claim `iss` z tokenu
2. Tworzy listę akceptowanych wydawców:
   - Zawsze zawiera wewnętrzny issuer
   - Jeśli zewnętrzny issuer jest skonfigurowany, dodaje go do listy
3. Sprawdza czy wydawca tokenu jest na liście akceptowanych

### Walidacja odbiorcy (aud/azp):
```python
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
```

#### Analiza:
1. **Warunek główny:** Walidacja wykonywana tylko jeśli `OIDC_AUDIENCE` jest skonfigurowany
2. **Claim `aud`:** Może być stringiem lub listą stringów
   - String: np. `"aud": "my-client-id"`
   - Lista: np. `"aud": ["my-client-id", "another-client"]`
3. **Claim `azp`:** "Authorized Party" - używany przez Keycloak gdy `aud` nie zawiera client_id
4. **Logika sprawdzania:**
   - Najpierw sprawdza `aud` (jako string lub lista)
   - Jeśli `aud` nie pasuje, sprawdza `azp` jako fallback
   - Jeśli żaden nie pasuje, token jest nieprawidłowy

### Zwrócenie claims:
```python
return claims
```
- Jeśli wszystkie walidacje przeszły, zwraca claims tokenu

### Obsługa wyjątków:
```python
except requests.RequestException as e:
    raise HTTPException(status_code=503, detail=f"OIDC JWKS unavailable: {str(e)}")
except JWTError as e:
    raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")
except HTTPException:
    raise
except Exception as e:
    raise HTTPException(status_code=401, detail=f"Token verification failed: {str(e)}")
```

#### Analiza każdego bloku except:

| Wyjątek | Status HTTP | Opis |
|---------|-------------|------|
| `requests.RequestException` | 503 | Błąd sieciowy (np. Keycloak niedostępny) |
| `JWTError` | 401 | Błąd parsowania/weryfikacji JWT |
| `HTTPException` | (zachowany) | Przepuszcza wyjątki już obsłużone (np. z wcześniejszych `raise HTTPException`) |
| `Exception` | 401 | Catch-all dla nieoczekiwanych błędów |

**Kolejność ma znaczenie:** `HTTPException` dziedziczy po `Exception`, więc musi być sprawdzony przed ogólnym `Exception`.

---

## 11. Funkcja `get_current_user`

```python
async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Security(security),
) -> Dict:
    token = credentials.credentials
    return verify_token(token)
```

### Szczegółowy opis:

#### Słowo kluczowe `async`:
- Funkcja jest asynchroniczna (współprogramowa)
- FastAPI automatycznie obsługuje funkcje async w endpointach
- Mimo że sama funkcja nie używa `await`, jest async dla kompatybilności z FastAPI

#### Parametr z dependency injection:
```python
credentials: HTTPAuthorizationCredentials = Security(security)
```
- **`credentials`** - parametr, który zostanie automatycznie wypełniony przez FastAPI
- **`HTTPAuthorizationCredentials`** - obiekt zawierający:
  - `scheme` - schemat autoryzacji (np. "Bearer")
  - `credentials` - sam token
- **`Security(security)`** - dekorator mówiący FastAPI aby:
  1. Użył `security` (instancji `HTTPBearer`) do wyodrębnienia tokenu
  2. Traktował to jako wymóg bezpieczeństwa (dokumentacja OpenAPI)

#### Pobranie tokenu:
```python
token = credentials.credentials
```
- Wyodrębnia sam token z obiektu `HTTPAuthorizationCredentials`
- Przykład: jeśli nagłówek to `Authorization: Bearer abc123`, to `credentials.credentials` = `"abc123"`

#### Weryfikacja i zwrot:
```python
return verify_token(token)
```
- Wywołuje funkcję `verify_token` do weryfikacji tokenu
- Jeśli weryfikacja przejdzie, zwraca claims użytkownika
- Jeśli weryfikacja się nie powiedzie, `verify_token` rzuci `HTTPException`

---

## Diagram przepływu uwierzytelniania

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            ŻĄDANIE HTTP                                      │
│                    Authorization: Bearer <token>                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          HTTPBearer (security)                               │
│                  Wyodrębnia token z nagłówka Authorization                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         get_current_user()                                   │
│                  Przekazuje token do verify_token()                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          verify_token(token)                                 │
│                                                                              │
│  1. Pobierz nagłówek JWT (kid)                                               │
│  2. Pobierz JWKS (get_jwks - z cache lub serwera)                           │
│  3. Znajdź klucz publiczny (_select_key)                                     │
│  4. Weryfikuj sygnaturę                                                      │
│  5. Sprawdź exp (wygaśnięcie)                                                │
│  6. Sprawdź iss (wydawca)                                                    │
│  7. Sprawdź aud/azp (odbiorca)                                               │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
          ┌─────────────────┐             ┌─────────────────┐
          │   SUKCES        │             │   BŁĄD          │
          │   Zwróć claims  │             │   HTTPException │
          │   użytkownika   │             │   401/503       │
          └─────────────────┘             └─────────────────┘
```

---

## Przykład struktury tokenu JWT

### Nagłówek (Header):
```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "abc123-key-id"
}
```

### Payload (Claims):
```json
{
  "exp": 1705680000,
  "iat": 1705676400,
  "iss": "https://keycloak.example.com/realms/myrealm",
  "aud": "my-frontend-app",
  "azp": "my-frontend-app",
  "sub": "user-uuid-12345",
  "preferred_username": "jan.kowalski",
  "email": "jan.kowalski@example.com",
  "realm_access": {
    "roles": ["user", "admin"]
  }
}
```

### Sygnatura:
```
RSASHA256(
  base64UrlEncode(header) + "." + base64UrlEncode(payload),
  privateKey
)
```

---

## Zmienne środowiskowe - podsumowanie

| Zmienna | Wymagana | Opis | Przykład |
|---------|----------|------|----------|
| `OIDC_ISSUER_URL` | Tak | URL wydawcy tokenów | `https://keycloak.example.com/realms/myrealm` |
| `OIDC_ISSUER_URL_EXTERNAL` | Nie | Alternatywny URL wydawcy | `https://auth.public.com/realms/myrealm` |
| `OIDC_AUDIENCE` | Nie | Client ID do walidacji | `my-frontend-app` |
| `OIDC_JWKS_URL` | Nie* | URL do JWKS | `https://keycloak.example.com/realms/myrealm/protocol/openid-connect/certs` |
| `SSL_VERIFY` | Nie | Weryfikacja SSL (domyślnie: true) | `true`, `false`, `0`, `no` |

\* `OIDC_JWKS_URL` jest automatycznie generowany z `OIDC_ISSUER_URL` jeśli nie podano.

---

## Kody błędów HTTP

| Kod | Sytuacja |
|-----|----------|
| 401 Unauthorized | Brak tokenu, nieprawidłowy token, wygasły token, zły wydawca, zły odbiorca |
| 403 Forbidden | HTTPBearer nie znalazł nagłówka Authorization |
| 503 Service Unavailable | Nie można połączyć się z serwerem JWKS (Keycloak niedostępny) |

---

## Bezpieczeństwo

1. **Weryfikacja kryptograficzna:** Token jest weryfikowany kryptograficznie za pomocą klucza publicznego RSA
2. **Walidacja czasowa:** Sprawdzany jest czas wygaśnięcia (`exp`)
3. **Walidacja wydawcy:** Sprawdzane jest źródło tokenu (`iss`)
4. **Walidacja odbiorcy:** Sprawdzane jest dla kogo token został wydany (`aud`/`azp`)
5. **Cache JWKS:** Klucze są cachowane przez 1 godzinę, z możliwością force refresh przy rotacji kluczy
6. **Obsługa rotacji kluczy:** Automatyczne odświeżanie JWKS gdy klucz nie zostanie znaleziony

