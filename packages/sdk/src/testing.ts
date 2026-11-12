// A host for `bun test`. Files, commands and HTTP are real. The board, the notes, the locks and the notifications live in memory.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import type { Activity, Card, CardAction, ExecOptions, HostInfo, Note, Notification, Page, PluginDefinition, RoutinesHost, StoredCard } from "./host.ts";
import { err, ok, type Result } from "./result.ts";

export type TestHost = {
  host: RoutinesHost;
  cards: Map<string, StoredCard>;
  notifications: Notification[];
  logs: string[];
  notes: Note[];
  // The delays of each runSoon call.
  soonRequests: number[];
  // What `activity.list` returns.
  activity: Activity;
  // Each page that changed, oldest first.
  pages: Page[];
  plugin: () => PluginDefinition | undefined;
};

const attempt = async <T>(run: () => T | Promise<T>): Promise<Result<T>> => {
  try {
    return ok(await run());
  } catch (cause) {
    return err((cause as Error).message);
  }
};

const execReal = async (cmd: string[], { cwd, stdin, timeoutMs, env }: ExecOptions = {}): Promise<Result<string>> => {
  const proc = Bun.spawn(cmd, {
    cwd,
    env: env && { ...process.env, ...env },
    timeout: timeoutMs,
    killSignal: "SIGKILL",
    stdin: stdin === undefined ? "ignore" : new Response(stdin),
    stdout: "pipe",
    stderr: "pipe",
  });
  const output = Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
  const code = await proc.exited;
  if (proc.signalCode) return err(`${cmd.slice(0, 3).join(" ")}: stopped by ${proc.signalCode}`);
  const [stdout, stderr] = await output;
  if (code === 0) return ok(stdout.trim());
  return err(`${cmd.slice(0, 3).join(" ")}: ${stderr.trim() || stdout.trim() || `exit ${code}`}`);
};

export const installTestHost = (overrides: Partial<Omit<RoutinesHost, "info">> & { info?: Partial<HostInfo> } = {}): TestHost => {
  const cards = new Map<string, StoredCard>();
  const notifications: Notification[] = [];
  const logs: string[] = [];
  const notes: Note[] = [];
  const held = new Set<string>();
  const soonRequests: number[] = [];
  const activity: Activity = { notifications: [], cards: [], failedRuns: [] };
  const pages: Page[] = [];
  let plugin: PluginDefinition | undefined;
  const { info, ...replaced } = overrides;

  const host: RoutinesHost = {
    info: {
      pluginId: "test",
      pluginDir: process.cwd(),
      stateDir: join(tmpdir(), "routines-test-state"),
      dataDir: join(tmpdir(), "routines-test-data"),
      home: homedir(),
      guardCommand: "/usr/bin/false",
      appCommand: "/usr/bin/false",
      timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      ...info,
    },
    log: (message) => void logs.push(message),
    exec: execReal,
    which: async (name) => {
      const path = Bun.which(name);
      return path ? ok(path) : err(`${name} is not on the PATH`);
    },
    fs: {
      exists: (path) => attempt(() => existsSync(path)),
      readText: (path) => attempt(() => readFileSync(path, "utf8")),
      writeText: (path, text, options) =>
        attempt(() => {
          mkdirSync(dirname(path), { recursive: true });
          writeFileSync(path, text, options?.mode ? { mode: options.mode } : undefined);
        }),
      readBase64: (path) => attempt(() => readFileSync(path).toString("base64")),
      writeBase64: (path, base64) =>
        attempt(() => {
          mkdirSync(dirname(path), { recursive: true });
          writeFileSync(path, Buffer.from(base64, "base64"));
        }),
      remove: (path) => attempt(() => rmSync(path, { recursive: true, force: true })),
      mkdir: (path) => attempt(() => void mkdirSync(path, { recursive: true })),
      list: (path) =>
        attempt(() =>
          readdirSync(path).map((name) => {
            const stats = statSync(join(path, name));
            return { name, isDirectory: stats.isDirectory(), modifiedAt: stats.mtime.toISOString() };
          }),
        ),
    },
    lock: {
      acquire: async (name) => {
        if (held.has(name)) return ok(false);
        held.add(name);
        return ok(true);
      },
      release: async (name) => ok(void held.delete(name)),
    },
    board: {
      upsert: async (card: Card) => ok(void cards.set(card.id, { ...card, updatedAt: new Date().toISOString() })),
      remove: async (id) => ok(void cards.delete(id)),
      list: async () => ok([...cards.values()]),
    },
    notify: async (notification) => ok(void notifications.push(notification)),
    runSoon: async (delayMs) => ok(void soonRequests.push(delayMs)),
    notes: { list: async () => ok([...notes]) },
    activity: { list: async () => ok(structuredClone(activity)) },
    page: {
      publish: async (blocks) => {
        if (JSON.stringify(pages.at(-1)?.blocks) !== JSON.stringify(blocks)) pages.push({ blocks, updatedAt: new Date().toISOString() });
        return ok(undefined);
      },
      get: async () => ok(pages.at(-1) ?? null),
    },
    http: async ({ url, method, headers, body, timeoutMs, redirect }) =>
      attempt(async () => {
        const response = await fetch(url, { method, headers, body, redirect, signal: timeoutMs ? AbortSignal.timeout(timeoutMs) : undefined });
        return { status: response.status, url: response.url, headers: [...response.headers.entries()], body: await response.text() };
      }),
    browser: {
      open: async () => err("the test host has no browser"),
      goto: async () => err("the test host has no browser"),
      waitFor: async () => err("the test host has no browser"),
      evaluate: async () => err("the test host has no browser"),
      close: async () => ok(undefined),
    },
    definePlugin: (definition) => {
      plugin = definition;
    },
    ...replaced,
  };

  globalThis.routines = host;
  return { host, cards, notifications, logs, notes, soonRequests, activity, pages, plugin: () => plugin };
};

// The actions that the manifest in `pluginDir` lists, for tests of the action list.
export const manifestActions = (pluginDir: string): CardAction[] => (JSON.parse(readFileSync(join(pluginDir, "plugin.json"), "utf8")) as { actions?: CardAction[] }).actions ?? [];
