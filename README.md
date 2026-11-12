# routines

A macOS app that runs your routines with AI agents on this Mac. Each routine is a plugin. The app runs the plugins on their schedules. Each plugin shows its work in a UI of its own, where you approve, answer and dismiss items.

The app ships with no plugins. You make them in a thread of the app, or you install them from a repo of your own.

[ARCHITECTURE.md](ARCHITECTURE.md) explains how the host works and what limits its plugins. The rules are in `.specify/memory/constitution.md`, and the specs are in `specs/`. [DESIGN.md](DESIGN.md) describes the look of the app and of each plugin UI.

## How it works

The app is written in Swift. Each plugin is TypeScript, bundled into one JavaScript file that runs in JavaScriptCore. A plugin reaches the Mac only through the host, and the host refuses each command, HTTP host and path that `plugin.json` does not list.

Each routine shows its items in its own UI, the first tab of its page. An item has a state: Planned, In progress, Needs you, Done or Failed. The Inbox lists the items of all routines that need you, and the sidebar counts them. A click on an Inbox row or on a notification opens the routine, and its UI shows the item.

Each routine has a Settings tab with its settings, its notes, its permissions and a switch to turn it off. Your notes go into the input of its agents. The Runs view lists each run and each action with its log.

## Setup

You need macOS 15 or later, Xcode with Swift 6, Bun and Claude Code. The threads can also use Codex.

1. Install the dependencies, run the checks and build the app:

   ```sh
   bun install
   bun run check
   bun run app:bundle
   ```

2. Move `build/Routines.app` to `/Applications` and open it.
3. Turn on "Open Routines at login" in a Settings tab.

## Plugins

The app loads plugins from these folders. A later folder replaces a plugin with the same id.

| Folder | Who writes it |
| --- | --- |
| `ROUTINES_PLUGINS_DIR` | You, during development. |
| `~/Library/Application Support/Routines/plugins` | You, or the install script of your plugin repo. |
| `~/Library/Application Support/Routines/workspace/plugins` | The coding agent of the threads. |

A plugin folder needs `plugin.json`, `dist/plugin.js` and, for a UI, `dist/ui`. After a change in one of the last two folders, the app loads the plugins again.

To keep plugins in a repo of your own, add `../routines/packages/sdk` and `../routines/packages/ui` to the `workspaces` of its `package.json`. Then its plugins import `@routines/sdk` and `@routines/ui` from this checkout. To make sure that each built plugin loads in the host, run this command:

```sh
cd app && ROUTINES_PLUGINS_DIR=<your repo>/plugins swift test --filter PluginBundleTests
```

## Daily use

| Task | How |
| --- | --- |
| Delete finished items | Choose a time in "Delete done and failed cards" in the Settings tab. |
| Teach a routine | Add a note in its Settings tab. |
| Make or change a routine | Open Threads, press New thread and describe the routine or the change. The agent builds it in the workspace, and the routine shows in the sidebar. Turn it on and fill its settings in its Settings tab. |
| Choose the coding agent | Open Threads and press the agent button at the top right. Choose Claude Code or Codex, and optionally a model and an effort. |
| Undo a routine of the agent | Ask the agent in a thread, or delete `~/Library/Application Support/Routines/workspace/plugins/<id>`. |
| Find a routine | Type its name in "Search routines" in the sidebar. |
| Pin a routine | Right-click the routine in the sidebar and choose Pin. Pinned routines show first. |
| See what a run did | Open Runs and select the run. |

## Recovery

| Failure | What happens |
| --- | --- |
| A plugin call hangs. | The host stops the call after the `timeoutMinutes` of the manifest. |
| The app quit during a run. | The run shows as failed, and the next slot runs the routine again. |

## Security

No design can promise that an agent is never hijacked, because agents read text from other people. The design limits what a hijacked agent can reach. The OS, the host, the credentials and the code enforce these limits. The prompts only add to them.

These risks remain:

- A plugin in `~/Library/Application Support/Routines/plugins` or in `workspace/plugins` runs with the permissions that its `plugin.json` lists. Read that file before you add or turn on a plugin.
- The thread agent runs without a sandbox in Claude Code auto mode, which judges each tool call. Codex runs in its workspace-write sandbox. Read the permissions of a routine that the agent made before you turn it on.

## Development

| Command | What it does |
| --- | --- |
| `bun run check` | Checks the tokens, type-checks the packages, runs their tests and runs the host tests. |
| `bun run build:workspace` | Writes `build/workspace`, the source of the workspace of the threads. |
| `bun run app:test` | Runs the host tests. |
| `bun run app:bundle` | Builds `build/Routines.app`. |

To run the app with the plugins of a folder, run this command:

```sh
cd app && ROUTINES_PLUGINS_DIR=<plugins folder> ROUTINES_WORKSPACE_SOURCE="$PWD/../build/workspace" swift run Routines
```

After you build a plugin again, choose File > Reload Plugins. To keep a test run away from your real cards and settings, also set `ROUTINES_DATA_DIR` to an empty folder.

A new feature starts with `/speckit-specify`. To write a plugin, read `specs/001-swift-host/contracts/plugin-api.md`.
