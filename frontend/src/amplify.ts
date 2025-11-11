import { getCognitoConfig } from "./config.ts";

const cfg = getCognitoConfig();

const awsconfig = {
  Auth: {
    Cognito: {
      userPoolId: cfg.userPoolId, // Get from Terraform output
      userPoolClientId: cfg.userPoolWebClientId, // Get from Terraform output
    },
  },
};

export default awsconfig;