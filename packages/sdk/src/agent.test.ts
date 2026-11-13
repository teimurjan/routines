import { expect, test } from "bun:test";
import { tmpdir } from "node:os";
import { z } from "zod";
import { MEMORY_TOOL, runNode, type NodeTask } from "./agent.ts";
import type { ExecOptions } from "./host.ts";
import { err, ok, type Result } from "./result.ts";
import { installTestHost } from "./testing.ts";

type Call = { cmd: string[]; options: ExecOptions };

const output = z.object({ fix: z.string() });

const cliOutput = JSON.stringify({ is_error: false, structured_output: { fix: "use the key" }, num_turns: 1 });

// A host whose `claude` answers from a list, one answer per call. Home is empty, so no user settings load.
const setup = (answers: Result<string>[]) => {
  const calls: Call[] = [];
  const test = installTestHost({
    info: { home: tmpdir(), pluginId: "asker", appCommand: "/Applications/Routines.app/Contents/MacOS/Routines" },
    exec: async (cmd, options = {}) => {
      calls.push({ cmd, options });
      return answers.shift() ?? err("no answer left");
    },
  });
  return { calls, logs: test.logs };
};

const task = (extra: Partial<NodeTask<typeof output>> = {}): NodeTask<typeof output> => ({
  name: "fix",
  prompt: "Fix it.",
  input: { bug: 1 },
  output,
  cwd: "/tmp/work",
  tools: { mode: "allowlist", allow: ["Read"] },
  ...extra,
});

const after = (cmd: string[], flag: string) => cmd[cmd.indexOf(flag) + 1];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

test("a new session passes a new session id and returns it with the output", async () => {
  const { calls } = setup([ok(cliOutput)]);
  const result = await runNode(task());
  const id = after(calls[0]!.cmd, "--session-id");
  expect(id).toMatch(UUID);
  expect(calls[0]!.cmd).not.toContain("--resume");
  expect(result).toEqual({ ok: true, value: { output: { fix: "use the key" }, session: { id: id!, cwd: "/tmp/work" } } });
});

test("a resume passes the stored id and runs in the stored folder", async () => {
  const { calls } = setup([ok(cliOutput)]);
  const result = await runNode(task({ session: { resume: { id: "s-1", cwd: "/tmp/first" } } }));
  expect(after(calls[0]!.cmd, "--resume")).toBe("s-1");
  expect(calls[0]!.cmd).not.toContain("--session-id");
  expect(calls[0]!.options.cwd).toBe("/tmp/first");
  expect(result.ok && result.value.session).toEqual({ id: "s-1", cwd: "/tmp/first" });
});

test("a failed resume runs once more in a new session with the history", async () => {
  const { calls, logs } = setup([err("claude -p --output-format: No conversation found with session ID: s-1"), ok(cliOutput)]);
  const history = [{ id: "9.3", at: "2026-11-13T10:00:00.000Z", action: "answered", actor: "you", trigger: "t", from: "waiting-on-you" as const, to: "waiting-on-you" as const, answer: "staging" }];
  const result = await runNode(task({ session: { resume: { id: "s-1", cwd: "/tmp/first" } }, history }));
  expect(calls).toHaveLength(2);
  expect(calls[1]!.cmd).not.toContain("--resume");
  expect(after(calls[1]!.cmd, "--session-id")).toMatch(UUID);
  expect(calls[1]!.options.stdin).toContain('"answer": "staging"');
  expect(logs).toContain("the session s-1 did not resume, so a new session started");
  expect(result.ok && result.value.output).toEqual({ fix: "use the key" });
});

test("a bad output of a resumed session is an error and starts no second call", async () => {
  const { calls } = setup([ok(JSON.stringify({ is_error: false, structured_output: { other: 1 } }))]);
  const result = await runNode(task({ session: { resume: { id: "s-1", cwd: "/tmp/first" } } }));
  expect(calls).toHaveLength(1);
  expect(result.ok).toBe(false);
});

test("memory adds the read-only search server of the routine and its one tool", async () => {
  const { calls } = setup([ok(cliOutput)]);
  await runNode(task({ memory: true }));
  const { cmd } = calls[0]!;
  expect(cmd.filter((arg) => arg === "--strict-mcp-config")).toHaveLength(1);
  expect(JSON.parse(after(cmd, "--mcp-config")!)).toEqual({
    mcpServers: { "routines-memory": { command: "/Applications/Routines.app/Contents/MacOS/Routines", args: ["--memory-mcp", "--routine", "asker"] } },
  });
  expect(cmd.slice(cmd.indexOf("--allowedTools") + 1)).toContain(MEMORY_TOOL);
});

test("a sandboxed node with memory passes --strict-mcp-config once", async () => {
  const { calls } = setup([ok(cliOutput)]);
  await runNode(task({ memory: true, tools: { mode: "sandboxed", allow: [], allowRead: [], denyRead: [] } }));
  expect(calls[0]!.cmd.filter((arg) => arg === "--strict-mcp-config")).toHaveLength(1);
});

test("without memory a node gets no memory server", async () => {
  const { calls } = setup([ok(cliOutput)]);
  await runNode(task());
  expect(calls[0]!.cmd).not.toContain(MEMORY_TOOL);
  expect(calls[0]!.cmd).not.toContain("--mcp-config");
});
