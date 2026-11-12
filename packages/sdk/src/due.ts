import { host } from "./host.ts";
import type { Result } from "./result.ts";
import { readText } from "./state-file.ts";

// In local time, because the host schedules by the clock of the Mac.
export const latestDailySlot = (now: Date, hour: number) => {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour);
  return today <= now ? today : new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1, hour);
};

// A run stays due until one finishes, so a closed laptop or a lost connection only delays it.
export const isDailyDue = (lastFinishedAt: Date | undefined, now: Date, hour: number) => !lastFinishedAt || lastFinishedAt < latestDailySlot(now, hour);

const readLastFinished = async (file: string) => {
  const saved = await readText(file);
  if (!saved.ok || saved.value === undefined) return undefined;
  const at = new Date(saved.value.trim());
  return Number.isNaN(at.getTime()) ? undefined : at;
};

// An error from `work` keeps the run due, so the next tick tries again.
export const runDailyWhenDue = async (file: string, hour: number, work: (slot: Date) => Promise<Result<unknown>>): Promise<Result<unknown>> => {
  const startedAt = new Date();
  if (!isDailyDue(await readLastFinished(file), startedAt, hour)) return { ok: true, value: undefined };
  const finished = await work(latestDailySlot(startedAt, hour));
  if (finished.ok) await host().fs.writeText(file, startedAt.toISOString());
  return finished;
};
