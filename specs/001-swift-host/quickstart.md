# Quickstart: Swift host with JavaScript plugins

You need macOS 15 or later, Xcode with Swift 6, Bun and the Claude Code CLI. The threads can also use Codex.

## Build and check

1. Install the dependencies: `bun install`.
2. Run all checks: `bun run check`. It checks the tokens, type-checks the packages, runs their tests and runs the host tests.
3. Build the app: `bun run app:bundle`. The app is `build/Routines.app`.

## Run the host tests

`bun run app:test` builds the prelude and runs `swift test` in `app/`. The tests load the fixture plugins in `app/Tests/RoutinesKitTests/Fixtures`:

| Fixture | What it covers |
| --- | --- |
| `plugins/echo` | The host calls, the web APIs, the refused calls, the item and plugin actions, `runSoon` and the schedule. |
| `plugins/broken` | A plugin without a bundle. It shows its problem and does not run. |
| `ui-plugin` | A plugin UI with item and plugin actions, with and without `confirm` and `input`. |
| `hostile-ui` | A page that tries to leave its web view. |

To run the WebKit tests of the plugin UI as well, set `ROUTINES_WEBKIT_TESTS=1`.

## Run the app with a small plugin

1. Make a plugin folder:

   ```sh
   mkdir -p ~/routines-dev/plugins/hello/dist
   ```

2. Write `~/routines-dev/plugins/hello/plugin.json`:

   ```json
   {
     "id": "hello",
     "name": "Hello",
     "description": "Adds one item that needs you, each minute.",
     "schedule": [{}],
     "runAtLaunch": true,
     "timeoutMinutes": 1
   }
   ```

3. Write `~/routines-dev/plugins/hello/dist/plugin.js`. A bundle can be plain JavaScript that uses the `routines` global:

   ```js
   routines.definePlugin({
     run: async ({ trigger }) => {
       await routines.exec(["ls"]);
       await routines.board.upsert({ id: "hello", title: "Hello from a plugin", body: `Trigger: ${trigger}`, column: "needs-you" });
       return { ok: true, value: "Added one item." };
     },
   });
   ```

4. Build the workspace source and start the app with an empty data folder:

   ```sh
   bun run build:workspace
   cd app && ROUTINES_DATA_DIR="$(mktemp -d)" ROUTINES_PLUGINS_DIR=~/routines-dev/plugins ROUTINES_WORKSPACE_SOURCE="$PWD/../build/workspace" swift run Routines
   ```

5. Make sure of these results:
   - The sidebar lists Hello. Its page shows the banner "This plugin has no UI."
   - The Inbox lists "Hello from a plugin" with the trigger `launch`.
   - Runs lists a run with the trigger `launch` and the result "Added one item."
   - The log of the run has `exec: denied: the command ls is not in permissions.exec`.
   - Each minute, Runs lists a new run with the trigger `schedule`.
6. In the Settings tab of Hello, turn off "Run this routine". The plugin page shows "the plugin is off", and no new run starts.
7. Delete `dist/plugin.js` and choose File > Reload Plugins. The sidebar shows a warning, and the Settings tab shows the problem.

`swift run` starts no app bundle, so the app shows no macOS notifications and has no login item. For both, use `build/Routines.app`.

## Check that a plugin folder loads

Each built plugin in a folder must load in JavaScriptCore and call `definePlugin`. To check this, run these commands:

```sh
bun run build:prelude
cd app && ROUTINES_PLUGINS_DIR=~/routines-dev/plugins swift test --filter PluginBundleTests
```

## Make a plugin in a thread

1. Open `build/Routines.app` and open Threads.
2. If the page shows that the agent is not ready, log in to Claude Code or Codex in Terminal.
3. Press New thread and send: "Make a routine that adds one item that needs you each hour."
4. The agent writes and builds the plugin in `~/Library/Application Support/Routines/workspace/plugins/<id>`. The plugin shows in the sidebar after the build.
5. Turn the plugin on and fill its required settings in its Settings tab.

To undo the plugin, ask the agent in the thread or delete its folder.

## Start an external action

1. Add a plugin action to the manifest of a plugin, and list its id in `permissions.external`:

   ```json
   "actions": [{ "id": "ping", "label": "Ping" }],
   "permissions": { "external": ["ping"] }
   ```

2. Add `onPluginAction: async ({ actionId }) => ({ ok: true, value: actionId })` to its bundle.
3. Copy the plugin folder to `~/Library/Application Support/Routines/plugins`, and open `build/Routines.app`.
4. Run `build/Routines.app/Contents/MacOS/Routines --perform <plugin id> ping`. The command prints `ping`.
