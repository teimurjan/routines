import { z } from "zod";
import { host, type Handoff, type Move, type State, type StoredActionable } from "./host.ts";
import { err, ok, type Result } from "./result.ts";

// A `read` or `reversible` transition of an owned actionable. The host refuses the other risks here.
export const moveTo = (id: string, transition: string, to: State, changes: Omit<Move, "to"> = {}): Promise<Result<StoredActionable>> =>
  host().actionables.move(id, { ...changes, transition, to });

// Hands an owned actionable to the routine that handles the new kind and state.
export const handTo = (id: string, change: Handoff): Promise<Result<StoredActionable>> => host().actionables.handoff(id, change);

// The output of a node that can ask you instead of deciding. The API needs an object at the root of the schema, so a union does not work.
export const asks = <Schema extends z.ZodType>(schema: Schema) =>
  z.object({
    question: z.string().describe("One question to the owner when you cannot decide alone, else empty."),
    result: schema.optional().describe("Your result when the question is empty."),
  });

export type Asked<Schema extends z.ZodType> = z.infer<ReturnType<typeof asks<Schema>>>;

// The question of the node, or its result. An empty question with no result breaks the contract.
export const answerOf = <Output>(output: { question: string; result?: Output }): Result<{ question: string } | { result: Output }> => {
  const question = output.question.trim();
  if (question) return ok({ question });
  return output.result === undefined ? err("the node returned neither a question nor a result") : ok({ result: output.result });
};
