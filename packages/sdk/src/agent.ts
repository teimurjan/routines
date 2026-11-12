import { z } from "zod";
import { host } from "./host.ts";
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

// The CLI validator does not know the draft 2020-12 meta-schema that Zod names.
const jsonSchema = (output: z.ZodType) => {
  const { $schema: _, ...schema } = z.toJSONSchema(output);
  return JSON.stringify(schema);
};

export const cliArgs = async (task: AgentTask<z.ZodType>): Promise<string[]> => [
  "claude",
  "-p",
  "--output-format",
  "json",
  "--json-schema",
  jsonSchema(task.output),
  ...toolFlags(task.tools),
  "--settings",
  await agentSettings(task),
  ...(task.model ? ["--model", task.model] : []),
  ...(task.effort ? ["--effort", task.effort] : []),
  ...(task.mcpConfig ? ["--mcp-config", task.mcpConfig] : []),
];

export const renderPrompt = ({ prompt, input }: Pick<AgentTask<z.ZodType>, "prompt" | "input">) =>
  `${prompt}\n\nInput:\n\n\`\`\`json\n${JSON.stringify(input, null, 2)}\n\`\`\`\n`;

export const runAgent: RunAgent = async (task) => {
  const stdout = await host().exec(await cliArgs(task), { cwd: task.cwd, stdin: renderPrompt(task), timeoutMs: RUN_TIMEOUT_MS, env: cliEnv(task) });
  if (!stdout.ok) return stdout;

  const json = parseJson(stdout.value);
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
