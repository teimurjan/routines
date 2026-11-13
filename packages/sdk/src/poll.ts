import type { z } from "zod";
import type { PluginDefinition, PollResult, RunContext } from "./host.ts";
import { jsonSchemaOf } from "./json-schema.ts";
import { err, ok } from "./result.ts";

export type PollDefinition<Output extends z.ZodType> = {
  // The task of this source in the shared poll.
  prompt: string;
  // It can read a file, so it can be async.
  input: (cursor: unknown, context: RunContext) => unknown;
  output: Output;
  // The items and the next cursor. The host saves the cursor only after it stores each item.
  toItems: (output: z.infer<Output>, cursor: unknown, context: RunContext) => PollResult;
};

// Builds `pollRequest` and `onPoll` of a source plugin from one Zod schema, so the request and the check cannot drift.
export const definePoll = <Output extends z.ZodType>({ prompt, input, output, toItems }: PollDefinition<Output>): Required<Pick<PluginDefinition, "pollRequest" | "onPoll">> => ({
  pollRequest: async ({ cursor }, context) => ok({ prompt, input: await input(cursor, context), output: jsonSchemaOf(output) }),
  onPoll: async ({ cursor, output: value }, context) => {
    const parsed = output.safeParse(value);
    return parsed.success ? ok(toItems(parsed.data, cursor, context)) : err(`the poll output breaks the contract: ${parsed.error.message}`);
  },
});
