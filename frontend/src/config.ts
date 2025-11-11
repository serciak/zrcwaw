export function getApiUrl(): string {
    return (window as any)._env_?.API_URL ?? "";
}

export function getCognitoConfig() {
    return {
        region: (window as any)._env_?.COGNITO_REGION ?? "",
        userPoolId: (window as any)._env_?.COGNITO_USER_POOL_ID ?? "",
        userPoolWebClientId: (window as any)._env_?.COGNITO_USER_POOL_WEB_CLIENT_ID ?? "",
    };
}