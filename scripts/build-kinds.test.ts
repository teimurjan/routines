import { expect, test } from "bun:test";
import { z } from "zod";
import { kindSchemas, missingKinds } from "../workspace/scripts/kinds.ts";

const bug = z.strictObject({ repo: z.string(), details: z.string().max(8000) });

test("each Zod export becomes the JSON Schema of its kind, without $schema", () => {
  const schemas = kindSchemas({ bug, "slack-message": z.object({ text: z.string() }), helper: () => 1, LIMIT: 3 });
  expect(Object.keys(schemas)).toEqual(["bug", "slack-message"]);
  expect(schemas.bug).toEqual({
    type: "object",
    properties: { repo: { type: "string" }, details: { type: "string", maxLength: 8000 } },
    required: ["repo", "details"],
    additionalProperties: false,
  });
});

test("a declared kind with no export is named", () => {
  expect(missingKinds(["bug", "note"], kindSchemas({ bug }))).toEqual(["note"]);
});
