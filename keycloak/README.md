# Konfiguracja Keycloak - Realm Export

## Spis treści

1. [Wprowadzenie](#wprowadzenie)
2. [Czym jest Keycloak?](#czym-jest-keycloak)
3. [Struktura pliku realm-export.json](#struktura-pliku-realm-exportjson)
4. [Ustawienia Realm](#ustawienia-realm)
5. [Konfiguracja Klientów (Clients)](#konfiguracja-klientów-clients)
   - [todos-spa (Frontend)](#todos-spa-frontend)
   - [todos-api (Backend)](#todos-api-backend)
6. [Protocol Mappers](#protocol-mappers)
7. [Użytkownicy testowi](#użytkownicy-testowi)
8. [Przepływ uwierzytelniania (Flow)](#przepływ-uwierzytelniania-flow)
9. [Zmienne szablonowe](#zmienne-szablonowe)
10. [Bezpieczeństwo](#bezpieczeństwo)

---

## Wprowadzenie

Plik `realm-export.json` zawiera pełną konfigurację realm'u Keycloak dla aplikacji Todos. Realm jest podstawową jednostką organizacyjną w Keycloak - izolowaną przestrzenią zawierającą użytkowników, role, grupy i konfigurację klientów (aplikacji).

Ten plik jest używany do automatycznego importu konfiguracji podczas uruchamiania Keycloak, co zapewnia powtarzalność wdrożeń (Infrastructure as Code).

---

## Czym jest Keycloak?

**Keycloak** to otwartoźródłowy serwer Identity and Access Management (IAM) rozwijany przez Red Hat. Implementuje standardy:

- **OpenID Connect (OIDC)** - warstwa tożsamości oparta na OAuth 2.0
- **OAuth 2.0** - protokół autoryzacji
- **SAML 2.0** - protokół federacji tożsamości

W naszej aplikacji Keycloak pełni rolę:
- **Authorization Server** - wydaje tokeny JWT
- **Identity Provider** - przechowuje i zarządza użytkownikami
- **Single Sign-On (SSO)** - centralne logowanie dla wszystkich aplikacji

---

## Struktura pliku realm-export.json

```
realm-export.json
├── Ustawienia realm (nazwa, flagi bezpieczeństwa)
├── clients[] - konfiguracja aplikacji klienckich
│   ├── todos-spa - aplikacja frontendowa (SPA)
│   └── todos-api - backend API
└── users[] - prekonfigurowani użytkownicy testowi
```

---

## Ustawienia Realm

```json
{
  "realm": "todos",
  "enabled": true,
  "sslRequired": "external",
  "registrationAllowed": true,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true
}
```

### Szczegółowy opis pól:

| Pole | Wartość | Opis |
|------|---------|------|
| `realm` | `"todos"` | **Nazwa realm'u** - unikalna nazwa identyfikująca ten realm. Używana w URL-ach (np. `/realms/todos`). Wszystkie zasoby (użytkownicy, klienci, role) są izolowane w ramach tego realm'u. |
| `enabled` | `true` | **Aktywność realm'u** - czy realm jest aktywny i może obsługiwać żądania uwierzytelniania. `false` wyłącza cały realm. |
| `sslRequired` | `"external"` | **Wymagania SSL** - określa kiedy wymagane jest HTTPS:<br>• `"all"` - zawsze wymagaj SSL<br>• `"external"` - wymagaj SSL tylko dla zewnętrznych żądań (nie localhost)<br>• `"none"` - nie wymagaj SSL (tylko dev!) |
| `registrationAllowed` | `true` | **Self-registration** - czy użytkownicy mogą się samodzielnie rejestrować przez stronę logowania Keycloak. Włączone dla wygody w środowisku dev. |
| `loginWithEmailAllowed` | `true` | **Logowanie emailem** - pozwala użytkownikom logować się za pomocą adresu email zamiast username. |
| `duplicateEmailsAllowed` | `false` | **Unikalne emaile** - każdy użytkownik musi mieć unikalny email. Zapobiega konfliktom przy logowaniu emailem. |
| `resetPasswordAllowed` | `true` | **Reset hasła** - czy użytkownicy mogą resetować hasło przez link "Zapomniałem hasła". |
| `editUsernameAllowed` | `false` | **Edycja username** - czy użytkownicy mogą zmieniać swój username po rejestracji. Wyłączone dla spójności. |
| `bruteForceProtected` | `true` | **Ochrona brute-force** - włącza automatyczne blokowanie konta po zbyt wielu nieudanych próbach logowania. Kluczowe dla bezpieczeństwa! |

---

## Konfiguracja Klientów (Clients)

W terminologii OAuth 2.0/OIDC, **klient** to aplikacja, która chce uzyskać dostęp do zasobów w imieniu użytkownika. W naszej architekturze mamy dwa klienty:

### todos-spa (Frontend)

```json
{
  "clientId": "todos-spa",
  "name": "Todos SPA Frontend",
  "enabled": true,
  "publicClient": true,
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "redirectUris": [
    "http://localhost:8080/*",
    "${frontend_url}/*"
  ],
  "webOrigins": [
    "http://localhost:8080",
    "${frontend_url}"
  ],
  "attributes": {
    "post.logout.redirect.uris": "http://localhost:8080/*##${frontend_url}/*"
  },
  "protocolMappers": [...]
}
```

#### Szczegółowy opis pól:

| Pole | Wartość | Opis |
|------|---------|------|
| `clientId` | `"todos-spa"` | **Identyfikator klienta** - unikalny ID używany podczas flow OAuth. Frontend używa tego ID w konfiguracji OIDC. |
| `name` | `"Todos SPA Frontend"` | **Nazwa wyświetlana** - przyjazna nazwa widoczna w konsoli administracyjnej Keycloak. |
| `enabled` | `true` | **Aktywność klienta** - czy klient może wykonywać operacje OAuth. |
| `publicClient` | `true` | **Klient publiczny** - ⚠️ **KLUCZOWE!** Oznacza, że klient nie może bezpiecznie przechowywać sekretu (client_secret). Aplikacje SPA działające w przeglądarce są z definicji publiczne - kod źródłowy jest widoczny dla użytkownika. Wymusza użycie PKCE (Proof Key for Code Exchange) dla bezpieczeństwa. |
| `standardFlowEnabled` | `true` | **Authorization Code Flow** - włącza standardowy przepływ OAuth 2.0 z przekierowaniami. Jest to najBEZPIECZNIEJSZY flow dla aplikacji SPA:<br>1. Użytkownik jest przekierowany do Keycloak<br>2. Loguje się<br>3. Keycloak przekierowuje z powrotem z kodem autoryzacyjnym<br>4. Frontend wymienia kod na tokeny |
| `directAccessGrantsEnabled` | `false` | **Resource Owner Password Credentials** - WYŁĄCZONE! Ten flow (wysyłanie username/password bezpośrednio do API) jest uważany za przestarzały i niebezpieczny dla aplikacji klienckich. |
| `redirectUris` | `["http://localhost:8080/*", "${frontend_url}/*"]` | **URI przekierowań** - whitelist URL-i, na które Keycloak może przekierować po uwierzytelnieniu. Zabezpieczenie przed atakiem open redirect. `*` pozwala na dowolną ścieżkę w danej domenie. |
| `webOrigins` | `["http://localhost:8080", "${frontend_url}"]` | **Dozwolone origin'y CORS** - określa, które domeny mogą wykonywać żądania cross-origin do Keycloak (np. pobieranie tokenów, userinfo). |
| `post.logout.redirect.uris` | `"http://localhost:8080/*##${frontend_url}/*"` | **URI przekierowań po wylogowaniu** - whitelist URL-i dla przekierowania po wylogowaniu. Separator `##` rozdziela wiele URL-i w Keycloak. |

#### Dlaczego `publicClient: true`?

Aplikacje SPA (Single Page Application) działają całkowicie w przeglądarce użytkownika. Oznacza to, że:
- Cały kod JavaScript jest widoczny (nawet minifikowany można zdekompilować)
- Nie ma bezpiecznego miejsca do przechowywania sekretu
- `client_secret` byłby ujawniony każdemu użytkownikowi

Dla klientów publicznych Keycloak wymusza użycie **PKCE** (Proof Key for Code Exchange) - mechanizmu, który zabezpiecza flow nawet bez sekretu.

---

### todos-api (Backend)

```json
{
  "clientId": "todos-api",
  "name": "Todos API Backend",
  "enabled": true,
  "bearerOnly": true,
  "standardFlowEnabled": false,
  "directAccessGrantsEnabled": false
}
```

#### Szczegółowy opis pól:

| Pole | Wartość | Opis |
|------|---------|------|
| `clientId` | `"todos-api"` | **Identyfikator klienta** - używany jako `audience` w tokenach JWT. Backend weryfikuje, czy token zawiera ten audience. |
| `name` | `"Todos API Backend"` | **Nazwa wyświetlana** - przyjazna nazwa w konsoli Keycloak. |
| `enabled` | `true` | **Aktywność klienta** - klient jest aktywny. |
| `bearerOnly` | `true` | **Tylko Bearer Token** - ⚠️ **KLUCZOWE!** Oznacza, że ten klient nigdy nie inicjuje procesu logowania. Tylko weryfikuje tokeny Bearer przekazane przez inne aplikacje. Jest to typowa konfiguracja dla API backendowego. |
| `standardFlowEnabled` | `false` | **Brak Authorization Code Flow** - backend nie loguje użytkowników, więc ten flow jest niepotrzebny. |
| `directAccessGrantsEnabled` | `false` | **Brak Resource Owner Password** - backend nie przyjmuje hasła użytkownika bezpośrednio. |

#### Czym jest Bearer Only?

Klient `bearerOnly` to "resource server" w terminologii OAuth 2.0:
- Nie ma strony logowania
- Nie wydaje tokenów
- Tylko **weryfikuje** tokeny JWT otrzymane w nagłówku `Authorization: Bearer <token>`
- Używa publicznych kluczy Keycloak (JWKS) do weryfikacji podpisu

---

## Protocol Mappers

Protocol Mappers to mechanizm Keycloak pozwalający na modyfikację zawartości tokenów JWT.

```json
"protocolMappers": [
  {
    "name": "todos-api-audience",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-audience-mapper",
    "consentRequired": false,
    "config": {
      "included.client.audience": "todos-api",
      "id.token.claim": "false",
      "access.token.claim": "true"
    }
  }
]
```

### Audience Mapper - szczegóły:

| Pole | Wartość | Opis |
|------|---------|------|
| `name` | `"todos-api-audience"` | **Nazwa mappera** - identyfikator w Keycloak. |
| `protocol` | `"openid-connect"` | **Protokół** - mapper dla OIDC (nie SAML). |
| `protocolMapper` | `"oidc-audience-mapper"` | **Typ mappera** - dodaje audience do tokenu. |
| `consentRequired` | `false` | **Zgoda użytkownika** - nie wymagaj dodatkowej zgody na ten mapper. |
| `included.client.audience` | `"todos-api"` | **Wartość audience** - dodaje `"todos-api"` do claimu `aud` w tokenie. |
| `id.token.claim` | `"false"` | **ID Token** - NIE dodawaj do ID tokena (używanego przez frontend do tożsamości). |
| `access.token.claim` | `"true"` | **Access Token** - DODAJ do access tokena (używanego do autoryzacji API). |

### Dlaczego potrzebujemy Audience Mapper?

Pole `aud` (audience) w JWT określa **dla kogo** token jest przeznaczony:

1. **Backend weryfikuje audience** - sprawdza czy `"todos-api"` jest w claimie `aud`
2. **Zabezpieczenie przed token confusion** - token wydany dla jednego API nie zadziała w innym
3. **Best practice OAuth 2.0** - zawsze weryfikuj audience

Przykład access tokena z audience:
```json
{
  "iss": "https://keycloak.example.com/realms/todos",
  "aud": ["todos-api"],
  "azp": "todos-spa",
  "sub": "user-uuid",
  "exp": 1737312000,
  ...
}
```

---

## Użytkownicy testowi

```json
"users": [
  {
    "username": "testuser",
    "email": "testuser@example.com",
    "enabled": true,
    "emailVerified": true,
    "firstName": "Test",
    "lastName": "User",
    "credentials": [
      {
        "type": "password",
        "value": "testpassword",
        "temporary": false
      }
    ]
  }
]
```

### Szczegółowy opis:

| Pole | Wartość | Opis |
|------|---------|------|
| `username` | `"testuser"` | **Nazwa użytkownika** - identyfikator do logowania. |
| `email` | `"testuser@example.com"` | **Email** - alternatywny identyfikator logowania (gdy `loginWithEmailAllowed: true`). |
| `enabled` | `true` | **Aktywność konta** - użytkownik może się logować. |
| `emailVerified` | `true` | **Email zweryfikowany** - oznacza email jako zweryfikowany (pomija krok weryfikacji). |
| `firstName`, `lastName` | `"Test"`, `"User"` | **Dane osobowe** - dostępne w ID tokenie i userinfo. |
| `credentials.type` | `"password"` | **Typ credentiala** - hasło. |
| `credentials.value` | `"testpassword"` | **Wartość hasła** - w plain text (Keycloak zahashuje przy imporcie). |
| `credentials.temporary` | `false` | **Hasło tymczasowe** - `false` = użytkownik nie musi zmieniać hasła przy pierwszym logowaniu. |

### ⚠️ Uwaga bezpieczeństwa

Ten użytkownik jest przeznaczony **TYLKO do testów**! W środowisku produkcyjnym:
- Nie definiuj użytkowników w realm-export
- Używaj silnych haseł
- Włącz `temporary: true` dla nowych użytkowników

---

## Przepływ uwierzytelniania (Flow)

Poniżej przedstawiono przepływ Authorization Code Flow z PKCE używany przez aplikację:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │     │   Frontend   │     │  Keycloak   │     │   Backend   │
│  (User)     │     │  (todos-spa) │     │  (OIDC)     │     │ (todos-api) │
└──────┬──────┘     └──────┬───────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                    │                   │
       │ 1. Klik "Zaloguj" │                    │                   │
       │──────────────────>│                    │                   │
       │                   │                    │                   │
       │                   │ 2. Generuj PKCE    │                   │
       │                   │    code_verifier   │                   │
       │                   │    code_challenge  │                   │
       │                   │                    │                   │
       │ 3. Redirect do Keycloak               │                   │
       │<──────────────────│                    │                   │
       │   /auth?client_id=todos-spa           │                   │
       │   &response_type=code                 │                   │
       │   &redirect_uri=...                   │                   │
       │   &code_challenge=...                 │                   │
       │──────────────────────────────────────>│                   │
       │                   │                    │                   │
       │ 4. Strona logowania Keycloak          │                   │
       │<──────────────────────────────────────│                   │
       │                   │                    │                   │
       │ 5. Wprowadź login/hasło               │                   │
       │──────────────────────────────────────>│                   │
       │                   │                    │                   │
       │                   │                    │ 6. Weryfikuj      │
       │                   │                    │    credentials    │
       │                   │                    │                   │
       │ 7. Redirect z authorization_code      │                   │
       │<──────────────────────────────────────│                   │
       │   /callback?code=abc123               │                   │
       │──────────────────>│                    │                   │
       │                   │                    │                   │
       │                   │ 8. POST /token     │                   │
       │                   │    code=abc123     │                   │
       │                   │    code_verifier=..│                   │
       │                   │───────────────────>│                   │
       │                   │                    │                   │
       │                   │                    │ 9. Weryfikuj PKCE │
       │                   │                    │    Wydaj tokeny   │
       │                   │                    │                   │
       │                   │ 10. access_token   │                   │
       │                   │     id_token       │                   │
       │                   │<───────────────────│                   │
       │                   │                    │                   │
       │ 11. Zalogowany!   │                    │                   │
       │<──────────────────│                    │                   │
       │                   │                    │                   │
       │ 12. Pobierz todos │                    │                   │
       │──────────────────>│                    │                   │
       │                   │                    │                   │
       │                   │ 13. GET /todos     │                   │
       │                   │     Authorization: │                   │
       │                   │     Bearer <token> │                   │
       │                   │───────────────────────────────────────>│
       │                   │                    │                   │
       │                   │                    │ 14. Pobierz JWKS  │
       │                   │                    │<──────────────────│
       │                   │                    │     (cache'd)     │
       │                   │                    │──────────────────>│
       │                   │                    │                   │
       │                   │                    │ 15. Weryfikuj JWT │
       │                   │                    │     - podpis      │
       │                   │                    │     - exp         │
       │                   │                    │     - iss         │
       │                   │                    │     - aud         │
       │                   │                    │                   │
       │                   │ 16. Response       │                   │
       │                   │<───────────────────────────────────────│
       │                   │                    │                   │
       │ 17. Lista todos   │                    │                   │
       │<──────────────────│                    │                   │
       │                   │                    │                   │
```

### Kluczowe elementy flow:

1. **PKCE (Proof Key for Code Exchange)** - zabezpiecza przed przechwyceniem authorization code
2. **Authorization Code** - jednorazowy, krótkotrwały kod wymieniany na tokeny
3. **Access Token** - JWT używany do autoryzacji żądań API
4. **ID Token** - JWT z informacjami o tożsamości użytkownika
5. **JWKS** - publiczne klucze do weryfikacji podpisu JWT (cache'owane przez backend)

---

## Zmienne szablonowe

Plik `realm-export.json` używa zmiennych szablonowych Terraform:

```json
"redirectUris": [
  "http://localhost:8080/*",
  "${frontend_url}/*"
]
```

### Jak to działa:

1. Terraform ładuje plik przez funkcję `templatefile()`
2. Podmienia `${frontend_url}` na rzeczywisty URL frontendu (np. `https://frontend-alb-xxx.amazonaws.com`)
3. Wygenerowany JSON jest używany przy imporcie realm'u

### Gdzie zdefiniowana jest zmienna:

W pliku `infra/keycloak.tf`:
```hcl
locals {
  realm_json = templatefile("${path.module}/../keycloak/realm-export.json", {
    frontend_url = "https://${aws_lb.frontend.dns_name}"
  })
}
```

---

## Bezpieczeństwo

### Zaimplementowane zabezpieczenia:

| Zabezpieczenie | Implementacja | Opis |
|----------------|---------------|------|
| **Brute Force Protection** | `bruteForceProtected: true` | Automatyczne blokowanie po nieudanych próbach |
| **HTTPS** | `sslRequired: "external"` | SSL dla wszystkich zewnętrznych połączeń |
| **PKCE** | `publicClient: true` | Wymuszenie PKCE dla klienta SPA |
| **Redirect URI Whitelist** | `redirectUris: [...]` | Tylko zaufane URI mogą otrzymać tokeny |
| **CORS** | `webOrigins: [...]` | Ograniczenie cross-origin requests |
| **Audience Verification** | `oid-audience-mapper` | Backend weryfikuje dla kogo token jest przeznaczony |
| **Bearer Only API** | `bearerOnly: true` | API nie ma strony logowania (mniejsza powierzchnia ataku) |
| **No Direct Access Grants** | `directAccessGrantsEnabled: false` | Wyłączenie niebezpiecznego password flow |

### Rekomendacje dla produkcji:

1. **Usuń użytkownika testowego** - lub ustaw silne hasło
2. **Rozważ `registrationAllowed: false`** - jeśli nie chcesz self-registration
3. **Skonfiguruj password policies** - minimalna długość, złożoność, history
4. **Włącz 2FA/MFA** - dodatkowa warstwa bezpieczeństwa
5. **Audit logging** - włącz logowanie zdarzeń bezpieczeństwa
6. **Token lifetimes** - dostosuj czas życia tokenów do potrzeb

---

## Powiązane pliki

- `infra/keycloak.tf` - Terraform konfiguracja infrastruktury Keycloak
- `backend/app/auth.py` - Weryfikacja JWT w backendzie
- `frontend/src/auth.ts` - Konfiguracja OIDC client w frontendzie
- `frontend/src/config.ts` - Konfiguracja URL-i i client_id

---

## Przydatne linki

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [OAuth 2.0 RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749)
- [OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html)
- [PKCE RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)
- [JWT RFC 7519](https://datatracker.ietf.org/doc/html/rfc7519)

