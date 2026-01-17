import { useEffect, useState } from "react";
import TodosList from "./TodosList.tsx";
import { getUserManager } from "./auth";
import type { User } from "oidc-client-ts";

function CallbackPage() {
  const um = getUserManager();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        await um.signinRedirectCallback();
        window.location.replace("/");
      } catch (e) {
        setError(String(e));
      }
    })();
  }, [um]);

  if (error) return <pre>Callback error: {error}</pre>;
  return <div>Logowanie...</div>;
}

export default function App() {
  const um = getUserManager();
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    (async () => {
      const u = await um.getUser();
      setUser(u);
    })();

    const onUserLoaded = (u: User) => setUser(u);
    const onUserUnloaded = () => setUser(null);

    um.events.addUserLoaded(onUserLoaded);
    um.events.addUserUnloaded(onUserUnloaded);

    return () => {
      um.events.removeUserLoaded(onUserLoaded);
      um.events.removeUserUnloaded(onUserUnloaded);
    };
  }, [um]);

  // Prosta obsługa callbacka bez routera
  if (window.location.pathname === "/auth/callback") {
    return <CallbackPage />;
  }

  if (!user || user.expired) {
    return (
      <div>
        <h3>Nie jesteś zalogowany</h3>
        <button onClick={() => um.signinRedirect()}>Zaloguj</button>
      </div>
    );
  }

  const profile = user.profile as Record<string, unknown>;
  const username =
    (typeof profile.preferred_username === "string" && profile.preferred_username) ||
    (typeof profile.email === "string" && profile.email) ||
    user.profile.sub;

  return (
    <div>
      <h3>Zalogowany: {username}</h3>
      <button onClick={() => um.signoutRedirect()}>Wyloguj</button>
      <TodosList />
    </div>
  );
}
