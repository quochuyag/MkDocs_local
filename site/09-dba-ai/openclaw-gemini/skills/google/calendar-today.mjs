import { calendarSummary } from "./lib/calendar.mjs";

const horizonHours = Number(process.env.CALENDAR_HORIZON_HOURS ?? 36);
const soonMinutes = Number(process.env.CALENDAR_SOON_MINUTES ?? 30);

const COLOR = {
  in_progress: "\x1b[35;1m",
  starting_soon: "\x1b[31;1m",
  today_later: "\x1b[33m",
  future: "\x1b[36m",
};
const RESET = "\x1b[0m";

const r = await calendarSummary({ horizonHours, soonMinutes });
const fmt = (d) => new Date(d).toLocaleString("vi-VN", { timeZone: r.timeZone, hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit" });

if (r.total === 0) {
  console.log(`No events in next ${horizonHours}h. Lịch trống.`);
  process.exit(0);
}

console.log(`Now: ${fmt(r.now)} (${r.timeZone})`);
console.log(`Horizon: next ${horizonHours}h, ${r.total} event(s)`);
console.log("Summary:");
for (const k of ["in_progress", "starting_soon", "today_later", "future"]) {
  console.log(`  ${COLOR[k]}${k.padEnd(15)}${RESET} ${r.groups[k].length}`);
}
if (r.overlaps.length > 0) console.log(`  \x1b[31;1moverlaps       ${RESET} ${r.overlaps.length}`);
console.log();

const byId = new Map(r.items.map((ev) => [ev.id, ev]));
for (const k of ["in_progress", "starting_soon", "today_later", "future"]) {
  const list = r.groups[k];
  if (list.length === 0) continue;
  const label = k === "starting_soon" ? `STARTING_SOON (≤${soonMinutes}min)` : k.toUpperCase();
  console.log(`${COLOR[k]}${label} (${list.length})${RESET}`);
  for (const ev of list) {
    const range = ev.allDay ? "(all-day)" : `${fmt(ev.start)} → ${fmt(ev.end)}`;
    console.log(`  ${range}  ${ev.title}`);
    if (ev.location) console.log(`    📍 ${ev.location}`);
    if (ev.conferenceLink) console.log(`    🔗 ${ev.conferenceLink}`);
    if (ev.attendees > 0) console.log(`    👥 ${ev.attendees} attendee(s)`);
  }
  console.log();
}

if (r.overlaps.length > 0) {
  console.log(`\x1b[31;1mOVERLAPS (${r.overlaps.length})${RESET}`);
  for (const ov of r.overlaps) {
    const a = byId.get(ov.a);
    const b = byId.get(ov.b);
    console.log(`  ${a.title}  (${fmt(a.start)} → ${fmt(a.end)})`);
    console.log(`  vs ${b.title}  (${fmt(b.start)} → ${fmt(b.end)})\n`);
  }
}
