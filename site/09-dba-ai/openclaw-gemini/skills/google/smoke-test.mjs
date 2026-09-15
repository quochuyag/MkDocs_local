import { google } from "googleapis";
import { loadAuth } from "./_client.mjs";

const auth = loadAuth();
const gmail = google.gmail({ version: "v1", auth });
const calendar = google.calendar({ version: "v3", auth });

console.log("\n[1/3] gmail.users.labels.list");
const labels = await gmail.users.labels.list({ userId: "me" });
console.log(`  ${labels.data.labels.length} labels (system + user)`);
console.log(`  e.g. ${labels.data.labels.slice(0, 5).map((l) => l.name).join(", ")}`);

console.log("\n[2/3] gmail.users.messages.list  q='is:unread newer_than:1d'");
const unread = await gmail.users.messages.list({ userId: "me", q: "is:unread newer_than:1d", maxResults: 5 });
const ids = unread.data.messages ?? [];
console.log(`  ${ids.length} unread message(s) in last 24h (showing up to 5)`);
for (const m of ids) {
  const msg = await gmail.users.messages.get({ userId: "me", id: m.id, format: "metadata", metadataHeaders: ["From", "Subject", "Date"] });
  const h = Object.fromEntries((msg.data.payload?.headers ?? []).map((x) => [x.name, x.value]));
  console.log(`  - ${h.Date ?? "?"} | ${h.From ?? "?"} | ${h.Subject ?? "(no subject)"}`);
}

console.log("\n[3/3] calendar.events.list  primary, timeMin=now, maxResults=5");
const now = new Date().toISOString();
const events = await calendar.events.list({ calendarId: "primary", timeMin: now, maxResults: 5, singleEvents: true, orderBy: "startTime" });
const items = events.data.items ?? [];
console.log(`  ${items.length} upcoming event(s)`);
for (const ev of items) {
  const start = ev.start?.dateTime ?? ev.start?.date ?? "?";
  console.log(`  - ${start} | ${ev.summary ?? "(no title)"}`);
}

console.log("\nAll three Google APIs answered without auth errors. Phase 1 done.");
