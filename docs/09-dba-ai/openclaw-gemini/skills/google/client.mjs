import { readFileSync, writeFileSync } from "node:fs";
import { google } from "googleapis";

const CREDENTIALS_PATH = "C:\\Users\\HHC_HOME\\.openclaw\\secrets\\google-quochuya-credentials.json";
const TOKENS_PATH = "C:\\Users\\HHC_HOME\\.openclaw\\secrets\\google-quochuya-tokens.json";

export function loadAuth() {
  const creds = JSON.parse(readFileSync(CREDENTIALS_PATH, "utf8")).installed;
  const store = JSON.parse(readFileSync(TOKENS_PATH, "utf8"));
  const oauth2 = new google.auth.OAuth2(creds.client_id, creds.client_secret, "http://localhost:53127/oauth2callback");
  oauth2.setCredentials(store.tokens);

  oauth2.on("tokens", (tokens) => {
    const merged = { ...store.tokens, ...tokens };
    if (!tokens.refresh_token && store.tokens.refresh_token) merged.refresh_token = store.tokens.refresh_token;
    writeFileSync(TOKENS_PATH, JSON.stringify({ ...store, tokens: merged, saved_at: new Date().toISOString() }, null, 2));
  });

  return oauth2;
}
