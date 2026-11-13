import { z } from "zod";
import { host, type Session, type Step } from "./host.ts";
import { jsonSchemaOf } from "./json-schema.ts";
import { log } from "./log.ts";
import { join } from "./path.ts";
import { err, ok, parseJson, type Result } from "./result.ts";
import { readText } from "./state-file.ts";

// A plugin that runs agents declares `claude` in `permissions.exec` and `~/.claude/settings.json` in `permissions.paths`.

// "allowlist" runs only the listed tools, and `connectors` keeps the claude.ai connectors available to that list.
// "sandboxed" adds a shell that the OS confines, with no network.
export type ToolPolicy =
  | { mode: "allowlist"; allow: string[]; connectors?: boolean }
  | { mode: "sandboxed"; allow: string[]; allowRead: string[]; denyRead: string[] };

// A call of `tool` runs only if its input equals one of `allowedInputs`.
export type ToolGuard = { tool: string; allowedInputs: Record<string, unknown>[] };

export type AgentTask<Output extends z.ZodType> = {
  name: string;
  // The prompt text. The input follows it as JSON.
  prompt: string;
  input: unknown;
  output: Output;
  cwd: string;
  tools: ToolPolicy;
  guard?: ToolGuard;
  model?: string;
  effort?: string;
  mcpConfig?: string;
};

export type RunAgent = <Output extends z.ZodType>(task: AgentTask<Output>) => Promise<Result<z.infer<Output>>>;

// A hung run holds the plugin, so it must end for the next run to start.
const RUN_TIMEOUT_MS = 2 * 60 * 60 * 1000;

const SANDBOXED_TOOLS = ["Bash", "Read", "Edit", "Write", "Glob", "Grep"];
const SECRET_READS = [
  "Read(**/.env*)", "Read(**/*.pem)", "Read(**/*.key)",
  ...[".ssh/**", ".aws/**", ".config/**", ".gnupg/**", ".kube/**", ".docker/**", ".npmrc", ".netrc"].map((path) => `Read(~/${path})`),
];

const userSettings = z.object({ enabledPlugins: z.record(z.string(), z.unknown()).optional() });

const claudeDir = () => join(host().info.home, ".claude");

// A node with connectors loads the user settings, but it needs no plugin. Plugins slow its start, and a channel plugin can take a bot from another session.
const disabledPlugins = async () => {
  const text = await readText(join(claudeDir(), "settings.json"));
  const json = text.ok && text.value !== undefined ? parseJson(text.value) : undefined;
  const settings = json?.ok ? userSettings.safeParse(json.value) : undefined;
  const names = Object.keys(settings?.success ? (settings.data.enabledPlugins ?? {}) : {});
  return Object.fromEntries(names.map((name) => [name, false]));
};

const cliResult = z.object({
  is_error: z.boolean(),
  result: z.string().optional(),
  structured_output: z.unknown().optional(),
  total_cost_usd: z.number().optional(),
  num_turns: z.number().optional(),
});

// --restricted drops settings, hooks, plugins and all MCP servers, and confines the file tools to the working directory.
// The claude.ai connectors need the user settings, so a node with connectors loads those and nothing from the project.
const allowlistScope = (connectors = false) => (connectors ? ["--setting-sources", "user"] : ["--restricted"]);

const toolFlags = (tools: ToolPolicy): string[] =>
  tools.mode === "allowlist"
    ? [...allowlistScope(tools.connectors), "--permission-mode", "dontAsk", "--allowedTools", ...tools.allow]
    : ["--restricted", "--tools", SANDBOXED_TOOLS.join(","), "--strict-mcp-config", "--permission-mode", "dontAsk", "--allowedTools", ...SANDBOXED_TOOLS, ...tools.allow];

// The OS enforces these limits on the shell and its children. --restricted covers the file tools, which run outside them.
const sandboxSettings = ({ allowRead, denyRead }: Extract<ToolPolicy, { mode: "sandboxed" }>) => ({
  enabled: true,
  failIfUnavailable: true,
  allowUnsandboxedCommands: false,
  autoAllowBashIfSandboxed: true,
  filesystem: { denyRead: ["~/", ...denyRead], allowRead },
  network: { strictAllowlist: true, allowedDomains: [] },
});

const guardHook = ({ tool }: ToolGuard) => ({
  PreToolUse: [{ matcher: tool, hooks: [{ type: "command", command: `"${host().info.guardCommand}" --tool-guard` }] }],
});

export const agentSettings = async ({ tools, guard }: Pick<AgentTask<z.ZodType>, "tools" | "guard">) =>
  JSON.stringify({
    enabledPlugins: await disabledPlugins(),
    permissions: { deny: SECRET_READS },
    ...(guard ? { hooks: guardHook(guard) } : {}),
    ...(tools.mode === "sandboxed" ? { sandbox: sandboxSettings(tools) } : {}),
  });

const cliEnv = ({ tools, guard }: AgentTask<z.ZodType>): Record<string, string> => ({
  CLAUDE_CONFIG_DIR: claudeDir(),
  ...(guard ? { ROUTINES_TOOL_GUARD: JSON.stringify(guard.allowedInputs) } : {}),
  // Git stops with an error if it cannot read ~/.gitconfig, which the sandbox denies.
  ...(tools.mode === "sandboxed" ? { CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1", GIT_CONFIG_GLOBAL: "/dev/null" } : {}),
});

export const cliArgs = async (task: AgentTask<z.ZodType>): Promise<string[]> => [
  "claude",
  "-p",
  "--output-format",
  "json",
  "--json-schema",
  JSON.stringify(jsonSchemaOf(task.output)),
  ...toolFlags(task.tools),
  "--settings",
  await agentSettings(task),
  ...(task.model ? ["--model", task.model] : []),
  ...(task.effort ? ["--effort", task.effort] : []),
  ...(task.mcpConfig ? ["--mcp-config", task.mcpConfig] : []),
];

export const renderPrompt = ({ prompt, input }: Pick<AgentTask<z.ZodType>, "prompt" | "input">) =>
  `${prompt}\n\nInput:\n\n\`\`\`json\n${JSON.stringify(input, null, 2)}\n\`\`\`\n`;

const callCli = (task: AgentTask<z.ZodType>, args: string[], cwd: string, stdin: string) =>
  host().exec(args, { cwd, stdin, timeoutMs: RUN_TIMEOUT_MS, env: cliEnv(task) });

// The JSON result of the CLI, checked against the output schema of the task.
const parseOutput = <Output extends z.ZodType>(task: AgentTask<Output>, stdout: string): Result<z.infer<Output>> => {
  const json = parseJson(stdout);
  if (!json.ok) return err(`${task.name}: ${json.error}`);
  const run = cliResult.safeParse(json.value);
  if (!run.success) return err(`${task.name}: unexpected claude output: ${run.error.message}`);

  const { is_error, result, structured_output, total_cost_usd, num_turns } = run.data;
  log(`${task.name}: ${num_turns ?? "?"} turns, $${total_cost_usd?.toFixed(2) ?? "?"}`);
  if (is_error) return err(`${task.name}: ${result ?? "claude reported an error"}`);

  const output = task.output.safeParse(structured_output);
  if (!output.success) return err(`${task.name}: output breaks the contract: ${output.error.message}`);
  return ok(output.data);
};

const execute = async <Output extends z.ZodType>(task: AgentTask<Output>, args: string[], cwd: string, stdin: string): Promise<Result<z.infer<Output>>> => {
  const stdout = await callCli(task, args, cwd, stdin);
  return stdout.ok ? parseOutput(task, stdout.value) : stdout;
};

export const runAgent: RunAgent = async (task) => execute(task, await cliArgs(task), task.cwd, renderPrompt(task));

export type NodeTask<Output extends z.ZodType> = AgentTask<Output> & {
  // A question step stores its session, and the answer resumes it.
  session?: { resume?: Session };
  // Adds the read-only memory search of the routine. See specs/004-actionables/contracts/memory.md.
  memory?: boolean;
  // The steps since the last answer. A new session gets them when the old one does not resume.
  history?: Step[];
};

export type NodeResult<Output extends z.ZodType> = { output: z.infer<Output>; session: Session };

export const MEMORY_TOOL = "mcp__routines-memory__search";

export const memoryMcpConfig = () =>
  JSON.stringify({
    mcpServers: { "routines-memory": { command: host().info.appCommand, args: ["--memory-mcp", "--routine", host().info.pluginId] } },
  });

const withMemoryTool = (tools: ToolPolicy): ToolPolicy => ({ ...tools, allow: [...tools.allow, MEMORY_TOOL] });

// The sandboxed policy already passes `--strict-mcp-config`, so it shows once.
const memoryArgs = (args: string[]) => [...(args.includes("--strict-mcp-config") ? [] : ["--strict-mcp-config"]), "--mcp-config", memoryMcpConfig()];

type SessionFlag = { resume: boolean; id: string };

const sessionArgs = ({ resume, id }: SessionFlag) => (resume ? ["--resume", id] : ["--session-id", id]);

export const nodeArgs = async (task: NodeTask<z.ZodType>, session: SessionFlag): Promise<string[]> => {
  const args = await cliArgs({ ...task, tools: task.memory ? withMemoryTool(task.tools) : task.tools });
  return [...args, ...(task.memory ? memoryArgs(args) : []), ...sessionArgs(session)];
};

const FENCE = "```";

const renderHistory = (history: Step[]) =>
  history.length === 0 ? "" : `\nThe earlier session did not resume. These are the steps since the last answer:\n\n${FENCE}json\n${JSON.stringify(history, null, 2)}\n${FENCE}\n`;

// Like runAgent, but it keeps the agent session, so a later answer can resume it.
export const runNode = async <Output extends z.ZodType>(task: NodeTask<Output>): Promise<Result<NodeResult<Output>>> => {
  const fresh = async (history: Step[]): Promise<Result<NodeResult<Output>>> => {
    const session = { id: crypto.randomUUID(), cwd: task.cwd };
    const output = await execute(task, await nodeArgs(task, { resume: false, id: session.id }), session.cwd, renderPrompt(task) + renderHistory(history));
    return output.ok ? ok({ output: output.value, session }) : output;
  };
  const resume = task.session?.resume;
  if (!resume) return fresh([]);

  // Only a failed CLI call counts as a failed resume. A bad output of a resumed session stays an error.
  const stdout = await callCli(task, await nodeArgs(task, { resume: true, id: resume.id }), resume.cwd, renderPrompt(task));
  if (!stdout.ok) {
    log(`the session ${resume.id} did not resume, so a new session started`);
    return fresh(task.history ?? []);
  }
  const output = parseOutput(task, stdout.value);
  return output.ok ? ok({ output: output.value, session: resume }) : output;
};
