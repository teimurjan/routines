import type { Result } from "./result.ts";

// The global `routines` object that the Swift host installs in each plugin context. See specs/001-swift-host/contracts/plugin-api.md.

export type Column = "planned" | "working" | "needs-you" | "done" | "failed";

// One action of the plugin. The manifest lists each one, and the plugin UI calls it. A card carries no actions.
export type CardAction = {
  id: string;
  label: string;
  style?: "primary" | "destructive" | "normal";
  // When set, the app asks for text and passes it as `ActionEvent.text`.
  input?: { placeholder: string };
  // When true, each press in the app asks you first. External actions skip the dialog.
  confirm?: boolean;
  // An item action needs the id of an item of the plugin. Absent means plugin.
  target?: "item" | "plugin";
};

export type Card = {
  id: string;
  title: string;
  // Markdown.
  body?: string;
  column: Column;
  // From 0 to 1.
  progress?: number;
  // ISO 8601.
  date?: string;
  tags?: string[];
  links?: { label: string; url: string }[];
  // Absolute paths of image files that the plugin wrote.
  images?: string[];
  // One line that the card shows under its body, for example the answer to the last action.
  status?: string;
  // Fields for the UI of the plugin. The host stores them without reading them, up to 32 KB as JSON.
  data?: Record<string, unknown>;
};

export type StoredCard = Card & { updatedAt: string };

export type Notification = { title: string; body: string; cardId?: string };

export type Note = { number: number; text: string };

// The work of the other plugins. `plugin` is the name of the plugin, and each list has the newest item first.
export type Activity = {
  notifications: { plugin: string; title: string; body: string; at: string }[];
  cards: { plugin: string; title: string; body?: string; column: Column; status?: string; links?: { label: string; url: string }[]; at: string }[];
  failedRuns: { plugin: string; message?: string; at: string }[];
};

// A part of the plugin page. The host draws it, so the page holds data and no code.
export type PageBlock =
  | { type: "markdown"; text: string }
  | { type: "status"; state: "ok" | "warning" | "error" | "neutral"; label: string; detail?: string };

// `updatedAt` is the last change of the blocks, in ISO 8601.
export type Page = { blocks: PageBlock[]; updatedAt: string };

export type ExecOptions = { cwd?: string; stdin?: string; timeoutMs?: number; env?: Record<string, string> };

export type HostInfo = {
  pluginId: string;
  pluginDir: string;
  // Shared by all plugins, so the state of the Bun routines carries over.
  stateDir: string;
  // The app's own folder in Application Support.
  dataDir: string;
  home: string;
  // A command that the Claude Code PreToolUse hook runs to check a tool input against ROUTINES_TOOL_GUARD.
  guardCommand: string;
  // The app binary. `<appCommand> --perform <plugin> <action> [text]` runs an external action and prints its answer.
  appCommand: string;
  timeZone: string;
};

export type HttpRequest = {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  bodyBase64?: string;
  timeoutMs?: number;
  redirect?: "follow" | "manual";
};

export type HttpResponse = { status: number; url: string; headers: [string, string][]; body: string; bodyBase64?: string };

export type FileEntry = { name: string; isDirectory: boolean; modifiedAt: string };

export type RoutinesHost = {
  info: HostInfo;
  log: (message: string) => void;
  exec: (cmd: string[], options?: ExecOptions) => Promise<Result<string>>;
  which: (name: string) => Promise<Result<string>>;
  fs: {
    exists: (path: string) => Promise<Result<boolean>>;
    readText: (path: string) => Promise<Result<string>>;
    writeText: (path: string, text: string, options?: { mode?: number }) => Promise<Result<void>>;
    readBase64: (path: string) => Promise<Result<string>>;
    writeBase64: (path: string, base64: string) => Promise<Result<void>>;
    remove: (path: string) => Promise<Result<void>>;
    mkdir: (path: string) => Promise<Result<void>>;
    list: (path: string) => Promise<Result<FileEntry[]>>;
  };
  // An in-process lock shared by all plugins. `acquire` waits until `timeoutMs` and returns false when it gives up.
  lock: {
    acquire: (name: string, timeoutMs?: number) => Promise<Result<boolean>>;
    release: (name: string) => Promise<Result<void>>;
  };
  board: {
    upsert: (card: Card) => Promise<Result<void>>;
    remove: (id: string) => Promise<Result<void>>;
    list: () => Promise<Result<StoredCard[]>>;
  };
  notify: (notification: Notification) => Promise<Result<void>>;
  // Asks for a run with the trigger "soon" after `delayMs`. A second request keeps the earlier time.
  runSoon: (delayMs: number) => Promise<Result<void>>;
  notes: { list: () => Promise<Result<Note[]>> };
  // Needs `permissions.activity`. Returns the activity since an ISO 8601 time.
  activity: { list: (since: string) => Promise<Result<Activity>> };
  // The page blocks that only the UI of the plugin shows. A publish of the same blocks changes nothing.
  page: {
    publish: (blocks: PageBlock[]) => Promise<Result<void>>;
    get: () => Promise<Result<Page | null>>;
  };
  http: (request: HttpRequest) => Promise<Result<HttpResponse>>;
  browser: {
    open: (profile: string) => Promise<Result<string>>;
    goto: (session: string, url: string, timeoutMs?: number) => Promise<Result<void>>;
    // Waits until the expression is truthy in the page.
    waitFor: (session: string, expression: string, timeoutMs?: number) => Promise<Result<boolean>>;
    // Runs the body of an async function in the page with `args` as its named arguments, and returns its JSON value.
    evaluate: (session: string, body: string, args?: Record<string, unknown>) => Promise<Result<unknown>>;
    close: (session: string) => Promise<Result<void>>;
  };
  definePlugin: (plugin: PluginDefinition) => void;
};

export type Trigger = "schedule" | "manual" | "launch" | "action" | "soon";

export type RunContext = { settings: Record<string, string>; trigger: Trigger };

export type ActionEvent = { cardId: string; actionId: string; text?: string };

// An action from `actions` in the manifest, which the app shows in the menu of the plugin page.
export type PluginActionEvent = { actionId: string; text?: string };

export type PluginDefinition = {
  run?: (context: RunContext) => Promise<Result<unknown> | void>;
  // Returns the line that the card shows as its status.
  onAction?: (event: ActionEvent, context: RunContext) => Promise<Result<string>>;
  // Returns the line that the plugin page shows under its menu.
  onPluginAction?: (event: PluginActionEvent, context: RunContext) => Promise<Result<string>>;
};

declare global {
  var routines: RoutinesHost;
}

export const host = (): RoutinesHost => globalThis.routines;
