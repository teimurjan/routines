import type { z } from "zod";

export type Result<T, E = string> = { ok: true; value: T } | { ok: false; error: E };

export const ok = <T>(value: T): Result<T, never> => ({ ok: true, value });

export const err = <E = string>(error: E): Result<never, E> => ({ ok: false, error });

export const parseJson = (text: string): Result<unknown> => {
  try {
    return ok(JSON.parse(text));
  } catch (cause) {
    return err(`invalid JSON: ${(cause as Error).message}`);
  }
};

// An agent can write "no error" as the literal text `""`, and that is not a failure.
export const hasAgentError = (error: string) => !/^["'\s]*$/.test(error);

export const parsed = <Schema extends z.ZodType>(schema: Schema, stdout: Result<string>, context: string): Result<z.infer<Schema>> => {
  if (!stdout.ok) return stdout;
  const json = parseJson(stdout.value);
  if (!json.ok) return json;
  const result = schema.safeParse(json.value);
  return result.success ? ok(result.data) : err(`${context}: ${result.error.message}`);
};
