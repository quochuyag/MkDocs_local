import { triageInbox } from "./lib/gmail.mjs";

const lookback = process.env.TRIAGE_LOOKBACK ?? "1d";
const maxMessages = Number(process.env.TRIAGE_MAX ?? 25);

const LABEL_COLOR = {
  important_reply: "\x1b[31;1m",
  important_fyi: "\x1b[33;1m",
  notification: "\x1b[36m",
  spam: "\x1b[90m",
};
const RESET = "\x1b[0m";

const result = await triageInbox({ lookback, maxMessages });

if (result.emails.length === 0) {
  console.log(`No unread messages in last ${lookback}. Inbox zero — nothing to triage.`);
  process.exit(0);
}

console.log(`Triaged ${result.emails.length} unread message(s) with ${result.model}\n`);
console.log("Summary:");
for (const label of ["important_reply", "important_fyi", "notification", "spam"]) {
  console.log(`  ${LABEL_COLOR[label]}${label.padEnd(18)}${RESET} ${result.groups[label].length}`);
}
console.log();

for (const label of ["important_reply", "important_fyi", "notification", "spam"]) {
  const items = result.groups[label];
  if (items.length === 0) continue;
  console.log(`${LABEL_COLOR[label]}${label.toUpperCase()} (${items.length})${RESET}`);
  for (const it of items) {
    const fromShort = it.from.length > 50 ? it.from.slice(0, 47) + "…" : it.from;
    const subjShort = it.subject.length > 70 ? it.subject.slice(0, 67) + "…" : it.subject;
    console.log(`  ${fromShort}`);
    console.log(`    ${subjShort}`);
    console.log(`    \x1b[2m${it.reason}${RESET}`);
  }
  console.log();
}

if (result.tokens) {
  console.log(`\x1b[2mTokens — input: ${result.tokens.input}, output: ${result.tokens.output}, total: ${result.tokens.total}${RESET}`);
}
