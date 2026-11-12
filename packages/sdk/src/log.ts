import { host } from "./host.ts";
import type { Result } from "./result.ts";

// The host adds the time and the plugin to each line.
export const log = (message: string) => host().log(message);

export const logFailures = (context: string, results: Result<unknown>[]) => {
  for (const result of results) if (!result.ok) log(`${context}: ${result.error}`);
};
