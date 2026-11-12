import type { StoredCard } from "@routines/sdk";
import { expect, test } from "bun:test";
import { byState } from "./groups.ts";

const item = (id: string, column: StoredCard["column"], updatedAt: string): StoredCard => ({ id, title: id, column, updatedAt });

test("the groups come in the order of what needs you first, each newest first, and empty groups are left out", () => {
  const groups = byState([
    item("old-done", "done", "2026-11-01T00:00:00.000Z"),
    item("old-ask", "needs-you", "2026-11-01T00:00:00.000Z"),
    item("new-ask", "needs-you", "2026-11-09T00:00:00.000Z"),
    item("failed", "failed", "2026-11-05T00:00:00.000Z"),
    item("working", "working", "2026-11-02T00:00:00.000Z"),
  ]);
  expect(groups.map(({ state, items }) => [state, items.map(({ id }) => id)])).toEqual([
    ["needs-you", ["new-ask", "old-ask"]],
    ["working", ["working"]],
    ["failed", ["failed"]],
    ["done", ["old-done"]],
  ]);
});

test("no items give no groups", () => {
  expect(byState([])).toEqual([]);
});
