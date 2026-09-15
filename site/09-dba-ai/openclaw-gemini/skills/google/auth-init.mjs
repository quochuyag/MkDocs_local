import { readFileSync, writeFileSync, chmodSync } from "node:fs";
import { createServer } from "node:http";
import { google } from "googleapis";
import open from "open";

const CREDENTIALS_PATH = "C:\\Users\\HHC_HOME\\.openclaw\\secrets\\google-quochuya-credentials.json";
const TOKENS_PATH = "C:\\Users\\HHC_HOME\\.openclaw\\secrets\\google-quochuya-tokens.json";

const SCOPES = [
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.modify",
  "https://www.googleapis.com/auth/calendar.readonly",
  "https://www.googleapis.com/auth/calendar.events",
];

const creds = JSON.parse(readFileSync(CREDENTIALS_PATH, "utf8")).installed;
if (!creds?.client_id) throw new Error("credentials.json missing 'installed.client_id'");

const PORT = 53127;
const REDIRECT_URI = `http://localhost:${PORT}/oauth2callback`;

const oauth2 = new google.auth.OAuth2(creds.client_id, creds.client_secret, REDIRECT_URI);

const authUrl = oauth2.generateAuthUrl({
  access_type: "offline",
  prompt: "consent",
  scope: SCOPES,
});

const code = await new Promise((resolve, reject) => {
  const server = createServer((req, res) => {
    try {
      const url = new URL(req.url, `http://localhost:${PORT}`);
      if (url.pathname !== "/oauth2callback") {
        res.writeHead(404).end();
        return;
      }
      const err = url.searchParams.get("error");
      if (err) {
        res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" }).end(`OAuth error: ${err}`);
        server.close();
        reject(new Error(err));
        return;
      }
      const c = url.searchParams.get("code");
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" }).end(
        "<html><body><h2>OpenClaw: Auth complete</h2><p>You can close this tab and return to the terminal.</p></body></html>",
      );
      server.close();
      resolve(c);
    } catch (e) {
      reject(e);
    }
  });
  server.listen(PORT, "127.0.0.1", () => {
    console.log(`Listening on ${REDIRECT_URI}`);
    console.log("Opening browser for Google consent…");
    open(authUrl).catch(() => console.log(`If the browser did not open, visit:\n${authUrl}`));
  });
  server.on("error", reject);
});

const { tokens } = await oauth2.getToken(code);
if (!tokens.refresh_token) {
  console.warn("WARNING: no refresh_token received. Revoke at https://myaccount.google.com/permissions and rerun.");
}

const out = {
  saved_at: new Date().toISOString(),
  client_id: creds.client_id,
  scopes: SCOPES,
  tokens,
};
writeFileSync(TOKENS_PATH, JSON.stringify(out, null, 2), { encoding: "utf8" });
try { chmodSync(TOKENS_PATH, 0o600); } catch {}

console.log(`Saved tokens to ${TOKENS_PATH}`);
console.log(`Scopes granted: ${tokens.scope ?? "(unknown)"}`);
console.log(`Access token expires at: ${tokens.expiry_date ? new Date(tokens.expiry_date).toISOString() : "(unknown)"}`);
console.log(`Refresh token present: ${tokens.refresh_token ? "yes" : "NO — re-auth will be required next run"}`);
