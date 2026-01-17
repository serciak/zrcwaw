import { UserManager, type User, WebStorageStateStore } from "oidc-client-ts";
import { getOidcConfig } from "./config";

let _userManager: UserManager | null = null;

export function getUserManager(): UserManager {
  if (_userManager) return _userManager;

  const cfg = getOidcConfig();

  _userManager = new UserManager({
    authority: cfg.authority,
    client_id: cfg.clientId,
    redirect_uri: cfg.redirectUri,
    post_logout_redirect_uri: cfg.postLogoutRedirectUri,
    response_type: "code",
    scope: cfg.scope,

    // Dla SPA: sessionStorage ogranicza długoterminowe przechowywanie tokenów.
    userStore: new WebStorageStateStore({ store: window.sessionStorage }),

    automaticSilentRenew: false,
    loadUserInfo: true,
  });

  return _userManager;
}

export async function getAccessToken(): Promise<string | undefined> {
  // używane w api.ts (interceptor)
  const um = getUserManager();
  const user: User | null = await um.getUser();
  if (!user || user.expired) return undefined;
  return user.access_token;
}
