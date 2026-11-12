# Architecture

Routines is a macOS app that runs scheduled jobs with AI agents on one Mac. A Swift host runs each job as a JavaScript plugin. A plugin shows its work in a UI of its own, and the Inbox lists the items of all plugins that need you. For setup and daily use, see [README.md](README.md). The rules are in `.specify/memory/constitution.md`. The specs are in `specs/`, and the design guide is [DESIGN.md](DESIGN.md).

## Terms

| Term | Meaning |
| --- | --- |
| Host | The Swift code in `app/Sources/RoutinesKit`. It knows no routine. |
| Plugin | A folder with `plugin.json` and one JavaScript bundle, in one of the plugin folders of the app. Each routine is a plugin. |
| Run | One call of the `run` function of a plugin. A clock slot starts it, or the plugin asks for it with `runSoon`. The app has no "Run now" button, so a plugin that needs a manual run adds an action for it. |
| Action | One call of `onAction` or `onPluginAction` of a plugin. The manifest lists each action, and a button in the plugin UI starts it. |
| Card | One item of work of a plugin. Its column is its state. |
| Plugin UI | A page that a plugin ships in `dist/ui`. The host shows it in a web view tab. |
| Inbox | The list of the items of all plugins that need you. |
| Page | The blocks that a plugin publishes for its UI, for example Markdown text or a status. |
| Node | One agent run with a typed input and a typed output. |
| Cursor | A file that records how far a routine read. |
| Ledger | A JSON file that records the work that a routine already did. |

## The main rules

Agents decide and code acts. A node reads its input and returns JSON. Then the plugin code rejects a bad result or does the outward actions. A node thus has only the tools that its task needs, and tests can cover each decision without an agent run.

A plugin reaches the Mac only through the host. The host checks each command, HTTP host, file path and browser call against the `permissions` of the manifest. A plugin cannot import Node or Bun, because it runs in JavaScriptCore.

Claude connectors, for example Slack and Gmail, are narrow exceptions, because a plugin reaches them only through an agent. A small node calls one connector tool, and a `PreToolUse` hook allows only the inputs that the code chose. The app binary is that hook: `Routines --tool-guard`.

## The host

```text
plugin.json + dist/plugin.js
   -> PluginCatalog          finds plugins in Application Support and in ROUTINES_PLUGINS_DIR
   -> PluginHost             schedules runs, queues actions, applies timeouts
   -> PluginRuntime          a new JavaScriptCore context per call, with the prelude
   -> Bridge                 checks each host call against the manifest
   -> Exec, File, HTTP, Lock and Browser services, and the stores

dist/ui (index.html, ui.js, ui.css)
   -> PluginUIScheme         serves routines-ui://<id>/ by the rules of PluginUIResources
   -> PluginWebView          one WKWebView per open tab, with the content rules and the navigation guard
   -> PluginUIBridge         turns each page message into a reply, a refusal or an action
   -> ActionGate             the one entry point for a press, with the host dialog
   -> PluginHost             one action queue per plugin
```

Each call of a plugin gets a new context on its own queue. The prelude in `packages/prelude` builds the `routines` global and the web APIs on one native function. That function returns a promise, and the bridge resolves it with the JSON of a `Result`.

One run of a plugin runs at a time. The actions of a plugin run one after another. They do not wait for a run, so a long run does not delay an approval. State that a run and an action both change goes through `updateStateFile` or `withLock`. The host lock is in memory, because all plugins run in one process.

The scheduler checks the clock slots of each manifest every 20 seconds and after each wake. One or more slots in the time since the last check start one run, so a Mac that slept runs each plugin once.

The stores are JSON files in `~/Library/Application Support/Routines`: the cards and the page per plugin, the notes, the settings, the notifications and the run index. Each run and each action writes a log file in `runs/<plugin>/`. The plugin state is in `~/.local/state/routines`.

Another program can start only the menu actions in `permissions.external` of the manifest. It runs `Routines --perform <plugin> <action> [text]`, which opens a `routines://` URL and prints the answer of the app.

The manifest lists each action of a plugin, with its target: one item or the plugin. A card carries no actions, and the app draws no action button and no menu. The host finds each action by its id in the manifest. It refuses an unknown id, a wrong target, an item that the plugin does not have and a text action without text. The handler of the plugin then checks that the action fits the state of the item. Each press comes from a plugin UI and goes through `ActionGate`. For an action with `confirm: true`, the gate shows a native dialog, and Cancel calls no handler. External actions skip the gate, because nobody is at the Mac to answer a dialog. `NativeActionsGoneTests` makes sure that no other app code calls an action.

### Plugin UI

A plugin with `ui` in its manifest ships a page in `dist/ui`. The build script of the workspace bundles `ui/main.tsx` of the plugin with Preact and writes the HTML from a fixed shell. The host shows the page in a `WKWebView` tab. The contract is in `specs/002-plugin-ui/contracts/plugin-ui.md`.

The page reaches nothing but its own plugin. Four layers hold it:

1. The scheme handler serves only the files of `dist/ui` and the images that a card of the plugin lists. Each response carries a strict content policy, so inline script and remote files do not run.
2. A content rule list blocks each load outside `routines-ui://`.
3. The navigation guard allows only the first load of the index. A link opens in the browser only through `openLink`.
4. Each web view has its own data store in memory, which goes away with the web view.

The page gets a snapshot with the items, the page blocks, the actions, the pending actions and the appearance of its plugin. The host sends a new snapshot after each change. The web view stays hidden until the page sends `ready`, or for 1 second, so no white frame shows.

`design/tokens.json` holds the colors, type sizes, spacing, radii and shadows. `bun run tokens` writes the Swift `Tokens` and the CSS of `packages/ui` from it, so the app and the plugin UIs share one style. `TokenUseTests` stops a style literal in the Swift views.

### Inbox

The Inbox lists the items of all plugins that need you, newest first. A row and a notification open the plugin, and its UI shows the item after the page is ready. A plugin of your own without a UI shows Runs and Settings under a banner.

### Threads

A thread is a conversation with your coding agent, Claude Code or Codex. You choose the agent, the model and the effort with the agent button on the Threads page. A thread keeps the agent that it started with, because a session of one CLI does not resume in the other. The host is the only code that runs the thread CLIs. A plugin cannot start a thread.

```text
ThreadService            one turn per thread, threads run side by side
   -> AgentCommand       claude -p --output-format stream-json --permission-mode auto [--resume id]
                         codex exec [resume id] --json -c sandbox_mode="workspace-write"
   -> AgentProcess       runs the CLI in the workspace, with the prompt on stdin
   -> AgentStream        turns each JSON line into thread events
   -> ThreadStore        threads/<id>.json in the data folder
```

Each turn starts with a `<routines-app>` block before your message. It lists the loaded routines, where each one comes from, and its problem or its last failed run. The agent thus sees a broken build on the next turn. Claude Code runs in auto mode, and Codex runs in its workspace-write sandbox. Neither one asks you in the app. The Claude session loads the settings of the workspace, so `.claude/settings.local.json` there can turn off a Claude plugin for the threads.

The agent works in `~/Library/Application Support/Routines/workspace`. `bun run build:workspace` writes its source to `build/workspace`, and the app bundle carries it. At launch, the host copies the source into the workspace when `version.txt` changed. The app owns each entry of the source: `AGENTS.md` with the rules for the agent, the SDK packages, the docs, the build script and `node_modules` with `zod`, `preact` and links to the packages. The agent owns `plugins/`, and an update never touches it. The build works offline, so Codex can build in its sandbox.

`workspace/plugins` is the last plugin folder, so a plugin there replaces an installed plugin with the same id. An FSEvents watcher on the folders of your plugins reloads the catalog after a change of a `plugin.json`, of a `dist/` file or of a plugin folder. A source edit does not reload. The UI tab of a plugin loads its page again after a new build.

## Layout

```text
DESIGN.md               The design guide: the tokens, the controls and the rules for plugin UIs.
design/tokens.json      The one source of the style. bun run tokens writes the Swift and CSS outputs.
app/                    The Swift package: RoutinesKit (the host), Routines (the app) and the tests.
packages/sdk/           The host API types, runAgent, state files, queues, card helpers and the test host.
packages/ui/            The Preact controls, the tokens CSS and the bridge client of plugin UIs.
packages/prelude/       The web APIs for JavaScriptCore.
workspace/              The AGENTS.md, CLAUDE.md, package.json and plugin build script of the workspace of the threads.
scripts/                Builds, the type check, the workspace source and the app bundle.
specs/                  Spec Kit features.
```

## Agent runner

Each node calls `runAgent` from `packages/sdk/src/agent.ts`. It runs `claude -p` through the host with the prompt on stdin and the Zod output schema as JSON Schema. The host kills the CLI after 2 hours. Then the SDK parses the output with the same schema and returns a `Result`.

## Untrusted text

Slack messages, PR text, web pages and emails come from other people. The prompts tell the agent to treat this text as data, but the real limits are the tools, the OS, the host and the code:

1. A node that reads such text gets no tool that writes to Slack, GitHub or files.
2. The host refuses each command, host and path that the manifest does not list.
3. The code cleans all agent text with `cleanOutgoing` before the text goes out under your name, and it escapes outside text in card bodies.

## Design rules

- Return a `Result` for expected failures. Do not throw.
- Run commands from an argument list, without a shell, so that text from a message cannot become a command.
- Keep the logic pure, and keep external calls in separate files in each plugin, for example `github.ts` or `google.ts`.
- Test the pure logic: markers, parsers, ledger decisions, card mappings and contract conversions. Do not test agent output.
- Keep the host free of routine code. If a plugin needs a new host feature, add a generic one to the contract.
- Take each color, font size and radius from `design/tokens.json`, in Swift and in CSS. See [DESIGN.md](DESIGN.md).
