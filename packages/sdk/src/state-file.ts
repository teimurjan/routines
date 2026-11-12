import type { z } from "zod";
import { host } from "./host.ts";
import { err, ok, parseJson, type Result } from "./result.ts";

const LOCK_TIMEOUT_MS = 5000;

// Runs `run` under a lock that all plugins share. Returns undefined when another holder keeps the lock past the timeout.
export const withLock = async <T>(name: string, run: () => Promise<T>, timeoutMs = LOCK_TIMEOUT_MS): Promise<T | undefined> => {
  const acquired = await host().lock.acquire(name, timeoutMs);
  if (!acquired.ok || !acquired.value) return undefined;
  try {
    return await run();
  } finally {
    await host().lock.release(name);
  }
};

export const readText = async (file: string): Promise<Result<string | undefined>> => {
  const exists = await host().fs.exists(file);
  if (!exists.ok) return exists;
  return exists.value ? host().fs.readText(file) : ok(undefined);
};

export const writeJson = (file: string, value: unknown) => host().fs.writeText(file, JSON.stringify(value, null, 2));

// A corrupt file returns an error, so a routine stops and does not forget its earlier work.
export const readStateFile = async <Schema extends z.ZodType>(file: string, schema: Schema, empty: z.infer<Schema>): Promise<Result<z.infer<Schema>>> => {
  const text = await readText(file);
  if (!text.ok) return text;
  if (text.value === undefined) return ok(empty);
  const json = parseJson(text.value);
  if (!json.ok) return err(`${file}: ${json.error}`);
  const parsed = schema.safeParse(json.value);
  return parsed.success ? ok(parsed.data) : err(`${file}: ${parsed.error.message}`);
};

// One read and one write under a lock, so two plugins that share a file cannot lose a change.
export const updateStateFile = async <Schema extends z.ZodType, Output>(
  file: string,
  schema: Schema,
  empty: z.infer<Schema>,
  change: (current: z.infer<Schema>) => { next: z.infer<Schema>; output: Output },
): Promise<Result<Output>> => {
  const updated = await withLock(file, async (): Promise<Result<Output>> => {
    const current = await readStateFile(file, schema, empty);
    if (!current.ok) return current;
    const { next, output } = change(current.value);
    const written = await writeJson(file, next);
    return written.ok ? ok(output) : written;
  });
  return updated ?? err(`${file}: another plugin holds its lock`);
};
