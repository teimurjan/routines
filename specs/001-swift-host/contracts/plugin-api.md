# Plugin API

A plugin is a folder with a manifest and one JavaScript bundle. The Swift host loads both and runs the bundle in a JavaScriptCore context of its own. The SDK is `@routines/sdk`, and its types are in `packages/sdk/src/host.ts`.

These contracts go with this one. In the workspace of the threads, they are in `docs/`.

| File | Repo folder | Topic |
| --- | --- | --- |
| `plugin-ui.md` | `specs/002-plugin-ui/contracts/` | The UI that a plugin ships in `dist/ui`. |
| `tokens.md` | `specs/002-plugin-ui/contracts/` | The style tokens of the app and the plugin UIs. |
| `actions.md` | `specs/003-custom-ui-everywhere/contracts/` | How the host finds an action, checks it and asks you first. |
| `ui-controls.md` | `specs/003-custom-ui-everywhere/contracts/` | The controls of `@routines/ui`. |

## Plugin folders

The app loads plugins from these folders, in this order. A later folder replaces a plugin with the same id.

| Folder | Who writes it |
| --- | --- |
| `ROUTINES_PLUGINS_DIR` | You, during development. |
| `<data folder>/plugins` | You, or the install script of a plugin repo. |
| `<data folder>/workspace/plugins` | The coding agent of the threads. |

The data folder is `~/Library/Application Support/Routines`. If `ROUTINES_DATA_DIR` is set, it is that folder. The host watches the last two folders. A change of a `plugin.json`, of a file in `dist/` or of a plugin folder loads the plugins again. A source edit does not. For `ROUTINES_PLUGINS_DIR`, choose File > Reload Plugins.

## Folder

| Path | Purpose |
| --- | --- |
| `plugin.json` | The manifest. Required. |
| `dist/plugin.js` | The bundle. Required. The `main` field of the manifest can name another path. |
| `src/index.ts` | The entry of the source. It calls `definePlugin` once. |
| `src/*.test.ts` | Unit tests for `bun test`. |
| `src/*.md`, `src/*.txt` | Text files, for example agent prompts. The build imports each one as a string: `import prompt from "./check.md";`. The module types are in `@routines/sdk/text`. |
| `package.json` | A name and the packages that the plugin imports, for example `@routines/sdk` and `zod`. |
| `tsconfig.json` | Extends `../../tsconfig.base.json` and includes `src`. |
| `ui/main.tsx` | Optional. The entry of the plugin UI, with `ui/tsconfig.json`. It imports `@routines/ui` and `preact`. |
| `dist/ui/` | The built UI: `index.html`, `ui.js` and `ui.css`. |

The host does not build plugins. In the workspace, `bun run build <id>` runs `scripts/build-plugins.ts` and writes `plugins/<id>/dist`. The script builds each folder in the `plugins/` folder next to its `scripts/` folder, so a plugin repo can use a copy of it.

The script bundles `src/index.ts` into one IIFE file for the browser target, with `.md` and `.txt` files as text. For a plugin with `ui/main.tsx`, it bundles the UI with the Preact JSX runtime. Then it writes `index.html` from a fixed shell. If the UI has no CSS, it writes an empty `ui.css`.

## Manifest

```json
{
  "id": "site-check",
  "name": "Site check",
  "description": "Checks a site every hour and tells you when it is down.",
  "color": "#0EA5E9",
  "emoji": "🌐",
  "schedule": [{ "minute": 0 }],
  "runAtLaunch": true,
  "timeoutMinutes": 5,
  "settings": [
    { "key": "url", "label": "Site URL", "required": true, "placeholder": "https://example.com" },
    { "key": "timeoutSeconds", "label": "Timeout in seconds", "default": "10" }
  ],
  "permissions": {
    "hosts": ["example.com", "*.example.com"],
    "external": ["check"]
  },
  "doneCards": { "retentionDays": 7 },
  "ui": { "title": "Checks" },
  "actions": [
    { "id": "check", "label": "Check now", "style": "primary" },
    { "id": "done", "label": "Done", "target": "item" }
  ]
}
```

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `id` | string | Required. | Must match the folder name. |
| `name` | string | Required. | The name in the sidebar, the Inbox and the notifications. |
| `description` | string | `""` | One line under the name on the plugin page. |
| `color` | `#RRGGBB` | `#6B7280` | The dot of a plugin without an emoji. The plugin UI gets it in its snapshot. |
| `icon` | string | `puzzlepiece` | An SF Symbols name. The host reads it, but the app does not draw it. |
| `emoji` | string | none | One emoji that stands for the plugin. An empty string counts as none. |
| `main` | string | `dist/plugin.js` | The path of the bundle in the folder. |
| `schedule` | clock slots | `[]` | The times of the runs. An empty list runs only at launch or on `runSoon`. |
| `runAtLaunch` | boolean | `false` | At each start of the app, also run once. |
| `timeoutMinutes` | integer | `150` | The longest time of one call of the plugin. |
| `settings` | setting fields | `[]` | The fields of the Settings tab. |
| `permissions` | object | all off | What the plugin can reach. |
| `doneCards` | `{ retentionDays }` | `{ "retentionDays": 14 }` | When the host deletes the done and failed cards. A negative value counts as 0. |
| `actions` | actions | `[]` | Each action of the plugin. |
| `ui` | `{ title }` | none | The plugin ships `dist/ui`. Its page shows the UI as the first tab, with the label `title`. |
| `hidden` | boolean | `false` | The sidebar leaves the plugin out. It still runs, and the Inbox lists its items. |

The host ignores keys that it does not know. A manifest that does not parse, an `id` that does not match the folder and a missing bundle each make a plugin with a problem. The sidebar shows a warning, the Settings tab shows the problem, and the plugin does not run.

### Clock slots

A slot has the optional fields `minute`, `hour`, `weekday` and `day`, as in launchd. `weekday` counts from Sunday as 0, and `day` is the day of the month. A field that is not there matches each value, so `{}` matches each minute. The host uses the time zone of the Mac.

### Settings

| Field | Default | Meaning |
| --- | --- | --- |
| `key` | Required. | The key in `RunContext.settings`. |
| `label` | the key | The label in the Settings tab. |
| `required` | `false` | The plugin does not run while the value is empty. |
| `shared` | `false` | One value for all plugins that declare the key. |
| `placeholder` | none | The hint in the empty field. |
| `default` | none | For an empty field, the value that the plugin gets. The empty field shows it as its hint. |

### Permissions

| Field | Type | Meaning |
| --- | --- | --- |
| `exec` | command names | The commands that `exec` can run. |
| `hosts` | host names | The hosts that `http`, `fetch` and `browser.goto` can reach. |
| `paths` | paths | The files and folders that `fs` and the `cwd` of `exec` can use. |
| `browser` | boolean | The plugin can open off-screen WebKit pages. |
| `activity` | boolean | The plugin can read the work of the other plugins. |
| `external` | action ids | The plugin actions that another program can start. |

The host compares the last part of the first word of a command with `exec`. For `env`, it also checks the command that `env` runs, and it refuses `env -S`.

The host compares each host name in lower case. `*.example.com` matches `example.com` and each subdomain. `*` matches each host.

A path in `paths` is absolute or starts with `~/`. The host resolves `..` and symbolic links before it checks a path. A path inside an allowed folder passes. These folders are always allowed:

- `~/.local/state/routines`, the state folder that all plugins share.
- The folder of the plugin.
- The data folder of the app.

A refused call returns `{ ok: false, error: "denied: <reason>" }`, and the host writes the refusal to the log of the call. The Settings tab lists the commands, hosts, paths, browser access and activity access of each plugin.

### Actions

Each action is `{ id, label, style, input, confirm, target }`.

| Field | Meaning |
| --- | --- |
| `id`, `label` | Required. The plugin UI shows the label on its control. |
| `style` | `primary`, `destructive` or `normal`. |
| `input` | `{ placeholder }`. The action needs text that is not blank. |
| `confirm` | `true` makes the app show a native dialog before each press in the app. Cancel calls no handler. |
| `target` | `item` acts on one item and calls `onAction`. `plugin`, or no target, acts on the plugin and calls `onPluginAction`. |

A card carries no actions, and the app draws no action control. A press comes from the plugin UI. The host finds the action by its id. It refuses an unknown id, a wrong target and an item that the plugin does not have. It also refuses an action with `input` but blank text. The full rules are in `actions.md`.

The app has no "Run now" button. An action that needs a run calls `runSoon`.

Another program starts an action in `permissions.external` with this command:

```sh
Routines --perform <plugin> <action> [text]
```

The command opens a `routines://perform` URL, waits up to 120 seconds for the answer and prints it. If the answer starts with `Error`, it exits with 1. Only a plugin action runs this way, and it shows no dialog. The `routines://` scheme works only for the app bundle, because `bun run app:bundle` registers it.

## Entry

```ts
import { definePlugin, ok } from "@routines/sdk";

definePlugin({
  run: async ({ settings, trigger }) => ok("Checked."),
  onAction: async ({ cardId, actionId, text }, { settings }) => ok("Done."),
  onPluginAction: async ({ actionId, text }, { settings }) => ok("Queued."),
});
```

Each function is optional. The bundle must call `definePlugin` at load. If it does not, each call fails with "the bundle did not call definePlugin".

| Function | The host calls it | Its value |
| --- | --- | --- |
| `run(context)` | At each due slot, at launch with `runAtLaunch`, and after a `runSoon` request. | A `Result` or nothing. A string value is the result line in Runs. |
| `onAction(event, context)` | When you press an item action. `event` is `{ cardId, actionId, text }`. | `Result<string>`. The value becomes the `status` of the card. |
| `onPluginAction(event, context)` | When you press a plugin action, or another program starts one. `event` is `{ actionId, text }`. | `Result<string>`. The plugin UI gets the value as `status` in its snapshot. |

`context` is `{ settings, trigger }`. `settings` holds the stored value of each field. For an empty value, it holds the `default`. A field with neither value is absent. `trigger` is `schedule`, `launch` or `soon` for a run, and `action` for an action. `manual` is the trigger of a direct call of the host, for example in a host test.

While an action runs, the card or the plugin shows "Working on it…". A value `{ ok: false, error }`, a thrown error, a rejected promise and a timeout each count as a failure. A failed action shows `Error: <error>`.

### Order and limits

- One `run` of a plugin runs at a time. A due run while one runs is skipped, and Runs records the skip.
- The item actions and the plugin actions of a plugin run one after another in one queue. They do not wait for a run, so you get an answer at once.
- Each call gets a new context, so calls share no variables. State that a run and an action both change goes through `updateStateFile` or `withLock`.
- A call that passes `timeoutMinutes` fails. The host then frees the locks and closes the browser pages of the call.
- A run does not start while the plugin has a problem, is off or misses a required setting. A blocked slot adds no record. A blocked launch run or `runSoon` run adds a skipped record.
- An action runs while the plugin is off or misses a setting. Only a plugin with a problem refuses its actions.

## Result

Each host call returns a `Result` and does not throw. The SDK exports these helpers from `packages/sdk/src/result.ts`.

| Helper | Purpose |
| --- | --- |
| `Result<T, E = string>` | `{ ok: true, value }` or `{ ok: false, error }`. |
| `ok(value)`, `err(error)` | Make a `Result`. |
| `parseJson(text)` | Parses JSON into a `Result`. |
| `parsed(schema, stdout, context)` | Parses the JSON of a command result with a Zod schema. |
| `hasAgentError(error)` | False for an empty error, or for an error that is only quotes and spaces. |

## Host API

`host()` returns the global `routines` object that the prelude installs.

| Call | What it does |
| --- | --- |
| `info` | `pluginId`, `pluginDir`, `stateDir`, `dataDir`, `home` and `timeZone`. `guardCommand` and `appCommand` are both the path of the app binary. |
| `log(message)` | Adds a line with the time to the log of the call. |
| `exec(cmd, { cwd, stdin, timeoutMs, env })` | Runs `cmd[0]` with the other items as arguments, without a shell. See [Commands](#commands). |
| `which(name)` | The path of a command on the PATH of the host. It needs no permission. |
| `fs.exists(path)` | Returns true for a file or folder that exists. |
| `fs.readText(path)`, `fs.readBase64(path)` | The content of a file as UTF-8 text or as base64. |
| `fs.writeText(path, text, { mode })`, `fs.writeBase64(path, base64)` | Writes a file atomically and creates its parent folders. `mode` sets the POSIX permissions, for example `0o600`. |
| `fs.remove(path)` | Removes a file or a folder with its content. A missing path is not an error. |
| `fs.mkdir(path)` | Makes a folder and its parents. |
| `fs.list(path)` | The entries of a folder: `{ name, isDirectory, modifiedAt }`. |
| `lock.acquire(name, timeoutMs = 5000)` | Waits for a lock that all plugins share. After `timeoutMs`, it returns false. |
| `lock.release(name)` | Frees a lock that this call holds. |
| `board.upsert(card)` | Adds a card, or replaces the card with the same id and keeps its place. |
| `board.remove(id)`, `board.list()` | Removes a card, or lists the cards of this plugin with `updatedAt`. |
| `notify({ title, body, cardId })` | Shows a macOS notification with the plugin name. A click opens the plugin, and its UI shows the item of `cardId`. |
| `runSoon(delayMs)` | Asks for one run with the trigger `soon`. See [Requested runs](#requested-runs). |
| `notes.list()` | Your notes for this plugin, oldest first: `{ number, text }`. |
| `activity.list(since)` | The work of the other plugins since an ISO 8601 time. It needs `permissions.activity`. |
| `page.publish(blocks)` | Replaces the page of this plugin. The same blocks change nothing and keep `updatedAt`. |
| `page.get()` | The page, or null. |
| `http(request)` | One HTTP request. See [HTTP](#http). |
| `browser.*` | Off-screen WebKit pages. See [Browser](#browser). |
| `definePlugin(plugin)` | Registers the functions of the plugin. The SDK `definePlugin` calls it. |

### Commands

The host looks for the command in this PATH: `~/.local/bin`, `~/.bun/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin` and `/sbin`. It sets `HOME` and adds the variables of `env`. The `cwd` must pass the path check.

`exec` returns the trimmed stdout. For an exit code other than 0, the error is the first three words of the command and then stderr, stdout or the exit code. After `timeoutMs`, the host kills the command with SIGKILL, and the error ends with "stopped by SIGKILL".

### Requested runs

The host keeps `delayMs` between 1 second and 1 hour. A second request keeps the earlier time, so a batch of actions starts one run. If a run is in progress at that time, the requested run starts after it.

### HTTP

`request` is `{ url, method, headers, body, bodyBase64, timeoutMs, redirect }`. Without a method, the host sends `GET`. Without a timeout, it waits 60 seconds. `redirect: "manual"` returns the redirect response and does not follow it.

The response is `{ status, url, headers, body, bodyBase64 }`. `headers` is a list of pairs with lower-case names. Each cookie is one `set-cookie` pair with `name=value`. A UTF-8 body is in `body`. Any other body is in `bodyBase64`, and `body` is empty.

The host keeps no cookies and no cache between requests, so a plugin sends its own cookies.

### Browser

Each call needs `permissions.browser`.

| Call | What it does |
| --- | --- |
| `open(profile)` | Opens a page in an off-screen window of 1280 by 900 points and returns a session id. |
| `goto(session, url, timeoutMs = 60000)` | Loads a URL and waits until the load ends. The host name of the URL must pass the check of `permissions.hosts`. |
| `waitFor(session, expression, timeoutMs = 60000)` | Checks the expression in the page every 250 ms. As soon as the expression is truthy, it returns true. After the timeout, it returns false. |
| `evaluate(session, body, args)` | Runs `body` as the body of an async function in the page, with the keys of `args` as named arguments. It returns the JSON value of the result, and `undefined` becomes null. |
| `close(session)` | Closes the page. |

A session belongs to the call that opened it. At the end of the call, the host closes each session of the call. The data store of a session comes from the call and the profile name. Two sessions of one call with the same profile share cookies. The next call gets a new store.

## Web APIs

The prelude in `packages/prelude` gives each context these APIs:

- `fetch`, `Headers`, `Response` and `AbortSignal.timeout`. `fetch` uses the `http` call and its permission check. A refused or failed request throws a `TypeError`. `AbortSignal` has only `timeout`.
- `URL` and `URLSearchParams`, from core-js.
- `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval` and `queueMicrotask`.
- `TextEncoder` and `TextDecoder` for UTF-8, `atob` and `btoa`.
- `crypto.randomUUID`, `crypto.getRandomValues`, `structuredClone` and `performance.now`.
- `console.log`, `info`, `debug`, `warn` and `error`. Each one writes to the log of the call.

The context has no Node and no Bun APIs. Code outside tests must not import `node:*` or `bun`.

## Cards

A card is one item of work of the plugin. Its column is its state.

| Field | Meaning |
| --- | --- |
| `id`, `title` | Required. The id is unique in the plugin. |
| `column` | `planned`, `working`, `needs-you`, `done` or `failed`. |
| `body` | Markdown. The Inbox shows its first line. |
| `progress` | From 0 to 1. |
| `date` | An ISO 8601 time or day. The Inbox shows it, or the time of the last change. |
| `tags` | Labels. The Inbox search matches them. |
| `links` | `{ label, url }` links. |
| `images` | Absolute paths of image files. The plugin UI can load only an image that a card of its plugin lists. |
| `status` | One line under the body, for example the answer to the last action. |
| `data` | A JSON object for the UI of the plugin. The host stores it and does not read it. If it is larger than 32 KB as JSON, the upsert fails. |

The host sets `updatedAt` on each write. The Inbox lists each card in `needs-you`, newest first. The plugin UI gets the cards of its plugin in its snapshot.

After `retentionDays` from its last change, the host deletes a card in `done` or `failed`. 0 keeps the cards. You can choose another retention in the Settings tab. Do not depend on a closed card that stays in the store.

A cards file that does not parse stops each write to it, so the host does not lose cards. Each write then returns the parse error.

## Page

A page is a list of blocks. The host stores the blocks, and the plugin UI gets them in its snapshot. A page holds data and no code.

| Block | Fields |
| --- | --- |
| `markdown` | `text`: Markdown text. |
| `status` | `state`: `ok`, `warning`, `error` or `neutral`. `label`: one or two words, for example `Online`. `detail`: one optional line. |

## Activity

`activity.list(since)` returns the work of the other loaded plugins, without the plugin that asks. Each list has the newest item first, and `plugin` is the name of the plugin.

| List | Fields |
| --- | --- |
| `notifications` | `plugin`, `title`, `body`, `at`. |
| `cards` | `plugin`, `title`, `body` (the first 600 characters), `column`, `status`, `links`, `at`. It leaves out `data`. |
| `failedRuns` | `plugin`, `message`, `at`. It holds the failed runs and the failed actions. |

## Agents

`runAgent(task)` runs one Claude Code agent through `exec` and returns `Result<output>`. It needs `claude` in `permissions.exec` and `~/.claude/settings.json` in `permissions.paths`. The `cwd` must also pass the path check.

| Field | Meaning |
| --- | --- |
| `name` | The name in the log lines and in the errors. |
| `prompt` | The prompt text. The SDK adds the input after it as a JSON block. |
| `input` | Any JSON value. |
| `output` | A Zod schema. The CLI gets it as JSON Schema, and the SDK parses the result with it. |
| `cwd` | The working folder of the agent. |
| `tools` | The tool policy. |
| `guard` | Optional. Limits one tool to the inputs that the code chose. |
| `model`, `effort`, `mcpConfig` | Optional. They become `--model`, `--effort` and `--mcp-config`. |

The SDK runs `claude -p --output-format json --json-schema <schema>` with the prompt on stdin. It sets `CLAUDE_CONFIG_DIR` to `~/.claude`, so the agent uses the Claude login of the Mac. The host kills the CLI after 2 hours. The SDK logs the turns and the cost. A CLI error and an output that breaks the schema each return an error.

Each agent gets settings that deny reads of secret files: `.env*`, `*.pem`, `*.key`, and `~/.ssh`, `~/.aws`, `~/.config`, `~/.gnupg`, `~/.kube`, `~/.docker`, `~/.npmrc` and `~/.netrc`. The settings also turn off each Claude plugin of the user settings.

| Tool policy | What the agent gets |
| --- | --- |
| `{ mode: "allowlist", allow }` | Only the tools in `allow`. `--restricted` drops the settings, hooks, plugins and MCP servers, and keeps the file tools in `cwd`. |
| `{ mode: "allowlist", allow, connectors: true }` | The same tools, with the user settings and no project settings, so the claude.ai connectors work. |
| `{ mode: "sandboxed", allow, allowRead, denyRead }` | `Bash`, `Read`, `Edit`, `Write`, `Glob` and `Grep`, plus `allow`. The OS confines the shell: no network, and no reads in the home folder outside `allowRead`. |

A `guard` is `{ tool, allowedInputs }`. The agent then runs `Routines --tool-guard` as the `PreToolUse` hook of that tool. If the input of a call has the same keys and values as one of `allowedInputs`, the hook allows the call. Each other call and each unreadable call is blocked.

## Other SDK helpers

| Helper | Purpose |
| --- | --- |
| `readText(file)` | The text of a file. For a missing file, it returns `undefined`. |
| `writeJson(file, value)` | Writes a value as indented JSON. |
| `readStateFile(file, schema, empty)` | Reads a JSON file with a Zod schema. A missing file returns `empty`. A file that does not parse returns an error, so a plugin does not forget its earlier work. |
| `updateStateFile(file, schema, empty, change)` | One read and one write under a lock with the name of the file. `change` returns `{ next, output }`. |
| `withLock(name, run, timeoutMs = 5000)` | Runs `run` under a shared lock. If the lock stays taken, it returns `undefined`. |
| `queueIn(file, schema, keyOf)` | A queue in a shared state file, with `read`, `push` and `remove`. `push` drops an item whose key is already in the queue. |
| `runDailyWhenDue(file, hour, work)` | Runs `work` once per day from `hour`, in local time. A failed `work` stays due for the next run. `isDailyDue` and `latestDailySlot` are the pure parts. |
| `moveCard(id, column, status)` | Moves a card. For a card that is gone or already in the column, it returns false. |
| `DONE_ACTION_ID`, `onDoneAction(event)` | The id `done` and a handler that moves the card of the event to `done`. |
| `myNotes()` | The texts of your notes. A failed read logs the error and returns an empty list. |
| `escapeMarkdown(text)` | Escapes Markdown, so outside text cannot add a link, an image or formatting to a card. |
| `cleanOutgoing(text, owners)` | Cleans agent text that goes out under your name. See below. |
| `hasSecret(text)` | Returns true for text with a known token pattern. |
| `log(message)`, `logFailures(context, results)` | Write to the log of the call. |
| `sleep(ms)`, `expandHome(path)` | A pause, and a `~` path to an absolute path. |
| `join`, `dirname`, `basename` | POSIX paths, because the context has no `node:path`. |
| `cliArgs`, `agentSettings`, `renderPrompt` | The parts of `runAgent`, for tests. |

`cleanOutgoing` replaces known token patterns with `[secret removed]`. It replaces each link with `[link removed]`, but it keeps an `https://github.com` link of an owner in `owners`. It removes the `<@…>`, `<#…>` and `<!…>` mention forms and puts a zero-width space after each `@` before a name. Then it cuts the text to 3000 characters.

## Tests

`@routines/sdk/testing` has a host for `bun test`.

| Export | Purpose |
| --- | --- |
| `installTestHost(overrides)` | Sets the global `routines` and returns a `TestHost`. `overrides` replaces any call or any `info` field. |
| `manifestActions(pluginDir)` | The `actions` of the manifest in a folder. |

The test host uses real files, real commands and real HTTP. It checks no permission. It keeps the cards, notifications, logs, notes, locks, `runSoon` delays, activity and pages in memory, and `TestHost` exposes each one. `plugin()` returns the definition that the bundle registered. The browser calls return an error.

To make sure that each built plugin of a folder loads in JavaScriptCore and calls `definePlugin`, run this command in `app/`:

```sh
ROUTINES_PLUGINS_DIR=<plugins folder> swift test --filter PluginBundleTests
```
