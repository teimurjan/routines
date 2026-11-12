<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo/wordmark/svg/routine-wordmark-white.svg">
    <img alt="Routines" src="logo/wordmark/svg/routine-wordmark-black.svg" width="420">
  </picture>
</p>

<p align="center">
  <b>Scheduled AI agents that run on your Mac and ask you before they act.</b>
</p>

<p align="center">
  macOS 15+ · Swift 6 · TypeScript · Claude Code or Codex
</p>

---

Routines is a macOS app that runs your routines on a schedule. A routine is a small plugin. It can check a site, read a feed, sort a queue or start an AI agent. Each routine shows its work in a UI of its own, where you approve, answer and dismiss items.

You do not need to write code to make a routine. Describe it in a thread, and the built-in coding agent writes, tests and builds it for you.

## Why Routines

- **It runs on your Mac.** Your files, your logins and your agents stay on your machine. A run uses your own Claude Code or Codex.
- **A plugin gets only what it declares.** Each plugin lists the commands, HTTP hosts and paths that it can reach. The host refuses everything else.
- **Agents decide, and code acts.** An agent returns typed JSON. Plugin code checks it before anything happens. An action that needs you waits for your click.
- **One Inbox.** Every item that needs you, from every routine, is in one list with a count in the sidebar.
- **A UI for each routine.** A plugin ships its own page, built with shared Preact controls that match the app.
- **The app starts empty.** You add only the routines that you want.

## Quick start

You need these tools:

- macOS 15 or later
- Xcode with Swift 6
- [Bun](https://bun.sh)
- [Claude Code](https://claude.com/claude-code). The threads can also use [Codex](https://github.com/openai/codex).

1. Clone the repo and build the app:

   ```sh
   git clone https://github.com/teimurjan/routines.git
   cd routines
   bun install
   bun run app:bundle
   ```

2. Move `build/Routines.app` to `/Applications` and open it.
3. If Claude Code is not logged in, run `claude` in a terminal and log in.

The app opens with no routines. Make your first one in the next section.

## Make your first routine

### Ask the agent

1. Open **Threads** and press **New thread**.
2. Describe the routine, for example:

   > Make a routine that checks https://example.com every hour. If the site is down, tell me.

3. The agent writes the plugin, runs its tests and builds it. The routine shows in the sidebar.
4. Open the routine, fill its settings in the **Settings** tab and turn it on.

To change a routine later, ask in the same thread or in a new one. To choose Claude Code or Codex, a model and an effort, press the agent button at the top right of Threads.

### Write it yourself

A plugin is a folder with `plugin.json` and one JavaScript bundle. The workspace of the threads has the SDK and a build script, so it is the fastest place to start.

1. Go to the workspace:

   ```sh
   cd ~/Library/Application\ Support/Routines/workspace
   ```

2. Write `plugins/hello/plugin.json`:

   ```json
   {
     "id": "hello",
     "name": "Hello",
     "description": "Says hello every morning.",
     "emoji": "👋",
     "schedule": [{ "hour": 9, "minute": 0 }],
     "runAtLaunch": true
   }
   ```

3. Write `plugins/hello/src/index.ts`:

   ```ts
   import { definePlugin, log, ok } from "@routines/sdk";

   definePlugin({
     run: async () => {
       log("Hello from Routines");
       return ok("Said hello.");
     },
   });
   ```

4. Build it:

   ```sh
   bun run build hello
   ```

The app loads the routine at once. Open **Runs** to see each run and its log.

The full API is in [the plugin API contract](specs/001-swift-host/contracts/plugin-api.md). It covers the manifest, permissions, settings, actions, cards, pages, agents and tests. For a routine with a UI, read [the plugin UI contract](specs/002-plugin-ui/contracts/plugin-ui.md) and [the UI controls](specs/003-custom-ui-everywhere/contracts/ui-controls.md).

## How it works

```text
plugin.json + dist/plugin.js       the manifest and the bundle of a routine
   -> the Swift host               runs each call in a new JavaScriptCore context
   -> the bridge                   checks each call against the manifest
   -> commands, files, HTTP, browser, Claude Code agents
dist/ui                            the page of the routine, in a locked-down web view
```

Each routine shows its items in its own UI, the first tab of its page. An item has a state: Planned, In progress, Needs you, Done or Failed. A click on an Inbox row or on a notification opens the routine at that item.

Each routine also has a **Settings** tab with its settings, notes, permissions and an on/off switch. Your notes go into the input of its agents. The **Runs** view lists each run and each action with its log.

[ARCHITECTURE.md](ARCHITECTURE.md) explains the host in detail. [DESIGN.md](DESIGN.md) describes the look of the app and of the plugin UIs.

## Where plugins live

The app loads plugins from these folders. A later folder replaces a plugin with the same id.

| Folder | Who writes it |
| --- | --- |
| `ROUTINES_PLUGINS_DIR` | You, during development. |
| `~/Library/Application Support/Routines/plugins` | You, or the install script of your plugin repo. |
| `~/Library/Application Support/Routines/workspace/plugins` | The coding agent of the threads. |

A plugin folder needs `plugin.json`, `dist/plugin.js` and, for a UI, `dist/ui`. When a file in the last two folders changes, the app loads the plugins again.

To keep your plugins in a repo of your own, clone it next to this repo. Add `../routines/packages/sdk` and `../routines/packages/ui` to the `workspaces` of its `package.json`. Copy `workspace/scripts/build-plugins.ts` into its `scripts/` folder. Then copy each built plugin into `~/Library/Application Support/Routines/plugins`.

## Everyday use

| Task | How |
| --- | --- |
| See what needs you | Open **Inbox**. The sidebar shows the count. |
| Teach a routine | Add a note in its **Settings** tab. |
| Turn a routine off | Use the switch in its **Settings** tab. |
| Delete finished items | Choose a time in "Delete done and failed cards" in the **Settings** tab. |
| See what a run did | Open **Runs** and select the run. |
| Find a routine | Type its name in "Search routines" in the sidebar. |
| Pin a routine | Right-click it in the sidebar and choose **Pin**. |
| Remove a routine of the agent | Ask the agent, or delete `~/Library/Application Support/Routines/workspace/plugins/<id>`. |
| Start Routines at login | Turn on "Open Routines at login" in a **Settings** tab. |

If a call of a plugin hangs, the host stops it after the `timeoutMinutes` of its manifest. If the app quits during a run, the run shows as failed, and the next slot runs the routine again.

## Security

No design can promise that an agent is never hijacked, because agents read text from other people. Routines limits what a hijacked agent can reach. The OS, the host and the code enforce these limits. The prompts only add to them.

- A plugin runs in JavaScriptCore, not in Node. It reaches the Mac only through the host, which refuses each command, HTTP host and path that the manifest does not list.
- A plugin UI runs in a web view with no network. It can reach only its own plugin.
- An action with `confirm: true` shows a native dialog before it runs.
- The app never puts a secret in the environment of an agent.

These risks remain:

- A plugin runs with the permissions that its `plugin.json` lists. Read that file before you add or turn on a plugin.
- The thread agent runs in Claude Code auto mode, which judges each tool call, without a sandbox. Codex runs in its workspace-write sandbox. Read the permissions of a routine that the agent made before you turn it on.

## Development

| Command | What it does |
| --- | --- |
| `bun run check` | Checks the tokens, type-checks the packages, runs their tests and runs the host tests. |
| `bun run app:test` | Runs the host tests. |
| `bun run app:bundle` | Builds `build/Routines.app`. |
| `bun run build:workspace` | Writes `build/workspace`, the source of the workspace of the threads. |
| `bun run tokens` | Writes the Swift and CSS style tokens from `design/tokens.json`. |

To run the app from the source with the plugins of a folder, run this command:

```sh
cd app && ROUTINES_PLUGINS_DIR=<plugins folder> ROUTINES_WORKSPACE_SOURCE="$PWD/../build/workspace" swift run Routines
```

After you build a plugin in `ROUTINES_PLUGINS_DIR` again, choose **File > Reload Plugins**. To keep a test run away from your real data, also set `ROUTINES_DATA_DIR` to an empty folder.

To make sure that each built plugin of a folder loads in the host, run this command:

```sh
cd app && ROUTINES_PLUGINS_DIR=<plugins folder> swift test --filter PluginBundleTests
```

| Folder | What it holds |
| --- | --- |
| `app/` | The Swift package: `RoutinesKit` (the host), `Routines` (the app) and the tests. |
| `packages/sdk/` | `@routines/sdk`: the host API, `runAgent`, state files, cards and the test host. |
| `packages/ui/` | `@routines/ui`: the Preact controls and the bridge client of plugin UIs. |
| `packages/prelude/` | The web APIs for JavaScriptCore. |
| `workspace/` | The rules, the build script and the package of the workspace of the threads. |
| `specs/` | The specs and the contracts of each feature. |

A new feature starts with `/speckit-specify`. The rules of the project are in [.specify/memory/constitution.md](.specify/memory/constitution.md).
