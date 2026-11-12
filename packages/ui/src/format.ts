const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

export const shortDay = (iso: string) => new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric" });

// "now", "5m", "3h" or "6d" for the last week, and the day after that.
export const timeAgo = (iso: string, now = new Date()) => {
  const elapsed = now.getTime() - Date.parse(iso);
  if (Number.isNaN(elapsed)) return "";
  if (elapsed < MINUTE) return "now";
  if (elapsed < HOUR) return `${Math.floor(elapsed / MINUTE)}m`;
  if (elapsed < DAY) return `${Math.floor(elapsed / HOUR)}h`;
  if (elapsed < 7 * DAY) return `${Math.floor(elapsed / DAY)}d`;
  return shortDay(iso);
};
