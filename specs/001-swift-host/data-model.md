# Data Model: Swift host with JavaScript plugins

## Folders

| Folder | Content |
| --- | --- |
| Data folder | `~/Library/Application Support/Routines`, or `ROUTINES_DATA_DIR`. The app writes each store here. |
| State folder | `~/.local/state/routines`. Plugins keep their own state files here. The host does not read them. |
| Plugin folders | `ROUTINES_PLUGINS_DIR`, `<data folder>/plugins` and `<data folder>/workspace/plugins`. |

Each store is one JSON file, written atomically. A file that does not parse returns an error, so a store does not write over it with an empty value.

| Path in the data folder | Store |
| --- | --- |
| `board/<plugin>.json` | The cards of a plugin. |
| `pages/<plugin>.json` | The page of a plugin. |
| `notes.json` | The notes of all plugins. |
| `settings.json` | The settings, the off switches, the pins, the retentions, the login item and the thread agent. |
| `notifications.json` | The newest 300 notifications. |
| `runs/index.json` | The newest 500 run records. |
| `runs/<plugin>/<start time>.log` | The log of a run. An action log ends with `-action.log`. |
| `threads/<id>.json` | One thread. |
| `replies/` | The answers to external actions. |
| `plugins/` | The installed plugins. |
| `workspace/` | The workspace of the threads. |

## Manifest

The `plugin.json` of a plugin. The fields and their defaults are in `contracts/plugin-api.md`. A manifest that does not parse makes an entry with the folder name as its id and name, and with a problem.

## Plugin entry

| Field | Meaning |
| --- | --- |
| `manifest` | The parsed manifest. |
| `dir` | The plugin folder. |
| `problem` | Why the plugin does not run: a manifest error, an id that does not match the folder, or a missing bundle. |
| `stamp` | The change times of the bundle and of `dist/ui/ui.js`. A new stamp loads the plugin UI again. |

The catalog sorts the entries by name.

## Card

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | Unique in its plugin. A write with the same id replaces the card and keeps its place. |
| `title` | string | Required. |
| `column` | `planned`, `working`, `needs-you`, `done` or `failed` | The state of the item. `done` and `failed` are closed. |
| `body`, `status` | string | Markdown, and one line under the body. |
| `progress` | number | From 0 to 1. |
| `date` | ISO 8601 | A time or a day. |
| `tags`, `links`, `images` | lists | Labels, `{ label, url }` links and absolute image paths. |
| `data` | JSON object | For the plugin UI. At most 32 KB as JSON. |
| `updatedAt` | time | The host sets it on each write. |

The host deletes a closed card after the retention of its plugin, counted from `updatedAt`. Your choice in the Settings tab replaces `doneCards.retentionDays` of the manifest, and 0 keeps the cards. The host checks the retention at each load, at each write and at each scheduler check.

## Run record

| Field | Meaning |
| --- | --- |
| `id`, `pluginId` | The record and its plugin. |
| `kind` | `run` or `action`. |
| `trigger` | For a run: `schedule`, `launch`, `soon` or `manual`. For an item action: `<card id>:<action id>`. For a plugin action: the action id. |
| `startedAt`, `endedAt` | The times of the call. |
| `outcome` | `running`, `succeeded`, `failed` or `skipped`. |
| `message` | The string value or the error that the call returned, or the reason of a skip. |
| `logFile` | The path of the log. |

At the next start, the host marks a record that was running at quit time as failed. Its end is the last change of its log file.

## Note

| Field | Meaning |
| --- | --- |
| `number` | Counts up across all plugins. |
| `text` | The trimmed text. The store ignores an empty note. |
| `at` | The time that you added it. |

Only the app writes notes. A plugin gets `number` and `text`, oldest first.

## Settings

| Field | Meaning |
| --- | --- |
| `shared` | The values of the shared keys. |
| `plugins` | The other values, per plugin. |
| `disabled` | The plugins that you turned off. |
| `pinned` | The pinned plugins, in the order that you pinned them. |
| `retentionDays` | Your retention of done cards, per plugin. |
| `launchAtLogin` | The login item. |
| `agent` | The thread agent: `provider` (`claude` or `codex`), `model` and `effort` (`low`, `medium`, `high` or `xhigh`). |

## Notification

`id`, `pluginId`, `title`, `body`, an optional `cardId` and `at`. The macOS notification shows the emoji and the name of the plugin as its subtitle.

## Page

`blocks` and `updatedAt`. A block is `markdown` or `status`. Only its plugin writes the page. The same blocks keep the file and the time.

## Thread

| Field | Meaning |
| --- | --- |
| `id` | The thread. |
| `provider` | `claude` or `codex`. It does not change after the thread starts. |
| `sessionId` | The CLI session that the next turn resumes. |
| `createdAt`, `updatedAt` | The times of the thread. |
| `items` | Your messages and the steps of the agent. |

An item has a kind: `user`, `message`, `reasoning`, `command`, `fileChange`, `tool` or `error`. It has a state: `running`, `done` or `failed`. A thread without items stays in memory only. The title is the first line of your first message, cut to 60 characters.

## Workspace

The source is `ROUTINES_WORKSPACE_SOURCE`, or the `workspace` folder in the resources of the app bundle. `bun run build:workspace` writes it to `build/workspace`. The app owns each top-level entry of the source. The agent owns `plugins/`. `version.txt` holds the build time of the source. The app writes it last, so a failed copy runs again at the next launch.

## State transitions of a run

```text
due slot, launch or runSoon request
  -> blocked (a problem, off or a missing required setting)
       from a slot: no record
       from launch or soon: skipped
  -> a run in progress: skipped ("previous run still running")
  -> running -> succeeded | failed (an error value, a thrown error or a timeout)
app quit during the run -> failed at the next start ("the app quit during the run")
```

## State transitions of an action

```text
press in a plugin UI, or an external request
  -> refused (an unknown id, a wrong target, an unknown item, blank text, or not in permissions.external)
  -> confirm: true and a press in the app -> host dialog -> Cancel: no call
  -> the plugin has a problem: "Error: <problem>", no record
  -> queued behind the earlier actions of the plugin
  -> running ("Working on it…") -> succeeded | failed ("Error: <error>")
```
