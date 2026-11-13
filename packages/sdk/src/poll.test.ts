import { expect, test } from "bun:test";
import { z } from "zod";
import { definePoll } from "./poll.ts";

const context = { settings: {}, trigger: "source" };

const poll = definePoll({
  prompt: "Find new notes.",
  input: (cursor) => ({ after: (cursor as { after?: string } | null)?.after ?? null }),
  output: z.object({ items: z.array(z.object({ key: z.string(), title: z.string() })) }),
  toItems: ({ items }, cursor) => ({
    items: items.map(({ key, title }) => ({ dedupeKey: key, kind: "note", title, data: {} })),
    cursor: items.length === 0 ? cursor : { after: items.at(-1)!.key },
  }),
});

test("the request holds the prompt, the input of the cursor and the schema without $schema", async () => {
  const request = await poll.pollRequest({ cursor: { after: "a" } }, context);
  expect(request.ok && request.value.prompt).toBe("Find new notes.");
  expect(request.ok && request.value.input).toEqual({ after: "a" });
  expect(request.ok && request.value.output).toMatchObject({ type: "object", required: ["items"] });
  expect(request.ok && "$schema" in request.value.output).toBe(false);
});

test("onPoll maps the items and moves the cursor", async () => {
  const output = { items: [{ key: "n1", title: "One" }, { key: "n2", title: "Two" }] };
  expect(await poll.onPoll({ cursor: null, output }, context)).toEqual({
    ok: true,
    value: { items: [{ dedupeKey: "n1", kind: "note", title: "One", data: {} }, { dedupeKey: "n2", kind: "note", title: "Two", data: {} }], cursor: { after: "n2" } },
  });
});

test("a bad part of the output is an error, so the host keeps the old cursor", async () => {
  const result = await poll.onPoll({ cursor: { after: "a" }, output: { items: [{ key: 1 }] } }, context);
  expect(result.ok).toBe(false);
});
