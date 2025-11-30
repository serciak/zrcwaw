import { getCognitoConfig } from "./config.ts";

const cfg = getCognitoConfig();

const awsconfig = {
  Auth: {
    Cognito: {
      userPoolId: cfg.userPoolId,
      userPoolClientId: cfg.userPoolWebClientId,
    },
  },
};

export default awsconfig;