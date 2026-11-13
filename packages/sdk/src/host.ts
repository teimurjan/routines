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

// The shared lifecycle of each actionable. See specs/004-actionables/data-model.md.
export type State = "new" | "ready" | "working" | "waiting-on-you" | "waiting-on-others" | "done" | "failed" | "dropped";

export type Risk = "read" | "reversible" | "outward" | "destructive";

export type Link = { label: string; url: string };

export type Session = { id: string; cwd: string };

export type Question = {
  text: string;
  // The transition that your answer starts.
  transition?: string;
  session?: Session;
  // Set on an `asked` step: the transition that waits for Allow.
  permission?: string;
};

export type Step = {
  id: string;
  at: string;
  // "transition:<id>", "handoff", "created", "updated", "asked", "answered", "denied", "board" or "migrated".
  action: string;
  actor: string;
  trigger: string;
  from: State;
  to: State;
  outcome?: string;
  question?: Question;
  answer?: string;
  oldOwner?: string;
  oldKind?: string;
};

export type Actionable = {
  id: string;
  kind: string;
  source: string;
  dedupeKey: string;
  owner: string | null;
  pastOwners: string[];
  state: State;
  title: string;
  body?: string;
  status?: string;
  tags?: string[];
  links: Link[];
  images?: string[];
  date?: string;
  progress?: number;
  data: Record<string, unknown>;
  steps: Step[];
  createdAt: string;
  updatedAt: string;
};

// `readOnly` is true for an actionable that the routine owned before.
export type StoredActionable = Actionable & { readOnly: boolean };

export type TransitionDeclaration = {
  id: string;
  label: string;
  from: State[];
  risk: Risk;
  input?: { placeholder: string };
  confirm?: boolean;
  style?: "primary" | "destructive" | "normal";
};

export type Move = {
  to: State;
  status?: string;
  title?: string;
  body?: string;
  data?: Record<string, unknown>;
  links?: Link[];
  question?: { text: string; transition: string; session?: Session };
};

export type Handoff = { state: State; kind?: string; title?: string; data?: Record<string, unknown> };

export type TransitionEvent = {
  actionable: StoredActionable;
  transition: string;
  text?: string;
  // Set when the trigger answers a question that carried a session.
  session?: Session;
  // The steps since the last answer, for a session that cannot resume.
  history: Step[];
};

// The task of one source in the shared poll. The input follows the prompt as JSON.
export type PollRequest = { prompt: string; input: unknown; output: Record<string, unknown> };

export type PollItem = { dedupeKey: string; kind: string; title: string; body?: string; data: Record<string, unknown>; links?: Link[] };

export type PollEvent = { cursor: unknown };

export type PollOutputEvent = { cursor: unknown; output: unknown };

export type PollResult = { items: PollItem[]; cursor: unknown };

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
  // The actionables of this routine. See specs/004-actionables/contracts/actionables.md.
  actionables: {
    list: (options?: { states?: State[]; past?: boolean }) => Promise<Result<StoredActionable[]>>;
    get: (id: string) => Promise<Result<StoredActionable | null>>;
    // Only a `read` or `reversible` transition. Use `request` for the others.
    move: (id: string, move: Move & { transition: string }) => Promise<Result<StoredActionable>>;
    request: (id: string, transition: string, text?: string) => Promise<Result<"queued" | "asked">>;
    handoff: (id: string, change: Handoff) => Promise<Result<StoredActionable>>;
  };
  notify: (notification: Notification) => Promise<Result<void>>;
  // Asks for a run with the trigger "soon" after `delayMs`. A request during a run queues one more run, and more requests merge into it.
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

// The trigger string of today: clock is "schedule", self is "soon", ui is "action", and each other source keeps its name.
export type Trigger = "schedule" | "manual" | "launch" | "action" | "soon" | "routine" | "external" | "answer" | "source";

export type TriggerSource = "clock" | "ui" | "self" | "routine" | "external" | "answer" | "source";

export type RunContext = {
  settings: Record<string, string>;
  trigger: Trigger | (string & {});
  source?: TriggerSource;
  // The actionable of a transition call.
  actionable?: string;
};

export type ActionEvent = { cardId: string; actionId: string; text?: string };

// An action from `actions` in the manifest, which the app shows in the menu of the plugin page.
export type PluginActionEvent = { actionId: string; text?: string };

export type PluginDefinition = {
  run?: (context: RunContext) => Promise<Result<unknown> | void>;
  // Returns the line that the card shows as its status.
  onAction?: (event: ActionEvent, context: RunContext) => Promise<Result<string>>;
  // Returns the line that the plugin page shows under its menu.
  onPluginAction?: (event: PluginActionEvent, context: RunContext) => Promise<Result<string>>;
  // The host calls it after the policy allows the trigger, and applies the move as one step.
  onTransition?: (event: TransitionEvent, context: RunContext) => Promise<Result<Move>>;
  // A source plugin: its part of the shared poll, then the items from its part of the output.
  pollRequest?: (event: PollEvent, context: RunContext) => Promise<Result<PollRequest>>;
  onPoll?: (event: PollOutputEvent, context: RunContext) => Promise<Result<PollResult>>;
};

declare global {
  var routines: RoutinesHost;
}

export const host = (): RoutinesHost => globalThis.routines;
