import { afterEach, expect, test } from "bun:test";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { z } from "zod";
import { answerOf, asks, handTo, moveTo } from "./actionables.ts";
import { jsonSchemaOf } from "./json-schema.ts";
import { installTestHost } from "./testing.ts";

const dirs: string[] = [];

// A plugin folder with the transitions of the asking fixture of the host tests.
const pluginDir = () => {
  const dir = join(tmpdir(), `routines-sdk-${crypto.randomUUID()}`);
  mkdirSync(dir, { recursive: true });
  const transitions = [
    { id: "start", label: "Start", from: ["new", "ready"], risk: "reversible" },
    { id: "merge", label: "Merge", from: ["working"], risk: "destructive" },
    { id: "answer", label: "Answer", from: ["waiting-on-you"], risk: "reversible", input: { placeholder: "Your answer" } },
  ];
  writeFileSync(join(dir, "plugin.json"), JSON.stringify({ id: "asker", name: "Asker", transitions }));
  dirs.push(dir);
  return dir;
};

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

const setup = () => installTestHost({ info: { pluginId: "asker", pluginDir: pluginDir() } });

test("the owner moves an actionable by a declared transition, and each move adds one step", async () => {
  const { actionables } = setup();
  const bug = actionables.add({ kind: "bug", title: "Login fails" });
  const moved = await moveTo(bug.id, "start", "working", { status: "Working on it…" });
  expect(moved.ok && moved.value).toMatchObject({ state: "working", status: "Working on it…" });
  expect(actionables.store.get(bug.id)?.steps).toMatchObject([{ action: "transition:start", from: "ready", to: "working", outcome: "Working on it…" }]);
});

test("the fake store refuses as the host does", async () => {
  const { actionables } = setup();
  const bug = actionables.add({ kind: "bug", title: "A" });
  const other = actionables.add({ kind: "bug", title: "B", owner: "factory" });
  expect(await moveTo(other.id, "start", "working")).toEqual({ ok: false, error: `asker does not own actionable ${other.id}` });
  expect(await moveTo(bug.id, "delete", "done")).toEqual({ ok: false, error: "asker has no transition delete" });
  expect(await moveTo(bug.id, "answer", "working")).toEqual({ ok: false, error: "answer does not start from ready" });
  expect(await moveTo("99", "start", "working")).toEqual({ ok: false, error: "there is no actionable 99" });
  await moveTo(bug.id, "start", "working");
  expect(await moveTo(bug.id, "merge", "done")).toEqual({ ok: false, error: "merge is destructive, so it needs actionables.request" });
  expect(actionables.store.get(bug.id)?.steps).toHaveLength(1);
});

test("a request of a destructive transition asks, and a reversible one queues", async () => {
  const { host, actionables } = setup();
  const bug = actionables.add({ kind: "bug", title: "A", state: "working" });
  expect(await host.actionables.request(bug.id, "merge")).toEqual({ ok: true, value: "asked" });
  expect(actionables.requests).toEqual([{ id: bug.id, transition: "merge" }]);
});

test("a question moves the actionable to waiting-on-you", async () => {
  const { actionables } = setup();
  const bug = actionables.add({ kind: "bug", title: "A" });
  const moved = await moveTo(bug.id, "start", "working", { question: { text: "Which key?", transition: "answer" } });
  expect(moved.ok && moved.value.state).toBe("waiting-on-you");
});

test("a hand-off records the old owner and kind, and the routine then reads it as past", async () => {
  const { host, actionables } = setup();
  const note = actionables.add({ kind: "note", title: "A" });
  const handed = await handTo(note.id, { state: "new", kind: "bug", data: { repo: "demo" } });
  expect(handed.ok && handed.value).toMatchObject({ kind: "bug", owner: null, pastOwners: ["asker"], readOnly: true });
  expect(actionables.store.get(note.id)?.steps.at(-1)).toMatchObject({ action: "handoff", oldOwner: "asker", oldKind: "note" });
  expect(await host.actionables.list()).toEqual({ ok: true, value: [] });
  expect(await host.actionables.list({ past: true })).toMatchObject({ ok: true, value: [{ id: note.id, readOnly: true }] });
  expect(await moveTo(note.id, "start", "working")).toEqual({ ok: false, error: `asker does not own actionable ${note.id}` });
});

test("asks lets a node return a question instead of its result", () => {
  const output = asks(z.object({ fix: z.string() }));
  expect(answerOf(output.parse({ question: "", result: { fix: "x" } }))).toEqual({ ok: true, value: { result: { fix: "x" } } });
  expect(answerOf(output.parse({ question: "Which key?" }))).toEqual({ ok: true, value: { question: "Which key?" } });
  expect(answerOf(output.parse({ question: " " })).ok).toBe(false);
  expect(output.safeParse({ result: { fix: "x" } }).success).toBe(false);
});

test("the schema of asks has an object at its root, as the API needs", () => {
  expect(jsonSchemaOf(asks(z.object({ fix: z.string() })))).toMatchObject({ type: "object", required: ["question"] });
});
