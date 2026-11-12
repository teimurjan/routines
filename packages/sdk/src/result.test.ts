import { expect, test } from "bun:test";
import { hasAgentError } from "./result.ts";

test("an empty error in any spelling is not a failure, so a good scan is kept", () => {
  for (const empty of ["", " ", '""', "''", ' "" ']) expect(hasAgentError(empty)).toBe(false);
});

test("a real error stays a failure", () => {
  expect(hasAgentError("Gmail connector is not available")).toBe(true);
  expect(hasAgentError('"Slack tools are missing"')).toBe(true);
});
