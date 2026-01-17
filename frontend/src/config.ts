type FrontendEnv = {
    API_URL?: string;
    OIDC_AUTHORITY?: string;
    OIDC_CLIENT_ID?: string;
    OIDC_REDIRECT_URI?: string;
    OIDC_POST_LOGOUT_REDIRECT_URI?: string;
    OIDC_SCOPE?: string;
};

declare global {
    interface Window {
        _env_?: FrontendEnv;
    }
}

function getEnv(): FrontendEnv {
    return window._env_ ?? {};
}

export function getApiUrl(): string {
    return getEnv().API_URL ?? "";
}

export function getOidcConfig() {
    const env = getEnv();
    const authority = env.OIDC_AUTHORITY ?? "";
    const clientId = env.OIDC_CLIENT_ID ?? "";

    // Jeśli nie podano w env, bierzemy z aktualnego originu.
    const fallbackRedirectUri = `${window.location.origin}/auth/callback`;
    const fallbackPostLogoutRedirectUri = `${window.location.origin}/`;

    return {
        authority,
        clientId,
        redirectUri: env.OIDC_REDIRECT_URI ?? fallbackRedirectUri,
        postLogoutRedirectUri: env.OIDC_POST_LOGOUT_REDIRECT_URI ?? fallbackPostLogoutRedirectUri,
        scope: env.OIDC_SCOPE ?? "openid profile email",
    };
}