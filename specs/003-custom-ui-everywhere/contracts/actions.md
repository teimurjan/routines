# Action contract

An action is one call of `onAction` or `onPluginAction` of a plugin. This contract describes how a plugin lists its actions, how the host checks each press and what the handler gets. [The plugin API](../../001-swift-host/contracts/plugin-api.md) and [the plugin UI contract](../../002-plugin-ui/contracts/plugin-ui.md) describe the rest of a plugin.

## Manifest

This example is a plugin that lists open tickets.

```json
{
  "id": "tickets",
  "name": "Tickets",
  "ui": { "title": "Tickets" },
  "actions": [
    { "id": "done", "label": "Done", "target": "item" },
    { "id": "close", "label": "Close", "style": "destructive", "confirm": true, "target": "item" },
    { "id": "comment", "label": "Comment", "input": { "placeholder": "Your comment" }, "target": "item" },
    { "id": "add", "label": "Add", "style": "primary", "input": { "placeholder": "A ticket title" } },
    { "id": "refresh", "label": "Refresh" }
  ],
  "permissions": { "external": ["add"] }
}
```

`actions` is the only list of actions of a plugin. A card has no `actions` field.

| Field | Required | Rule |
| --- | --- | --- |
| `id` | Yes | The id that the page sends and that the handler gets. |
| `label` | Yes | The label of the button and the action name in the host dialog. |
| `style` | No | `primary`, `destructive` or `normal`. The default is `normal`. |
| `input` | No | `{ "placeholder": "..." }`. The action then needs text that is not blank. |
| `confirm` | No | With `true`, the host shows its dialog before each press from the app. |
| `target` | No | `item` or `plugin`. The default is `plugin`. |

An item action acts on one item of the plugin and calls `onAction`. A plugin action acts on the plugin and calls `onPluginAction`.

## Calls from the page

| Message | Action | Handler |
| --- | --- | --- |
| `perform` with `cardId`, `actionId` and `text?` | An item action of the manifest | `onAction({ cardId, actionId, text }, context)` |
| `performPluginAction` with `actionId` and `text?` | A plugin action of the manifest | `onPluginAction({ actionId, text }, context)` |

`context` is `{ settings, trigger: "action" }`. Use `ActionButton` of `@routines/ui`, or `perform` and `performPluginAction` of `usePlugin()`. Do not call `postMessage` yourself.

## What the host refuses

The host finds each action by its id in the manifest and checks its target. It refuses each of these calls and calls no handler. The page gets `{ ok: false, error }` with this error:

| Call | Error |
| --- | --- |
| `perform` without `cardId` | `perform needs a cardId` |
| A message without `actionId` | `the message needs an actionId` |
| An id that the manifest does not list | `denied: <plugin> has no action <id>` |
| `perform` of a plugin action | `denied: <id> is not an item action` |
| `performPluginAction` of an item action | `denied: <id> needs an item` |
| `perform` with an item that the plugin does not have | `denied: <plugin> has no card <cardId>` |
| An action with `input` and no text or blank text | `the action <label> needs text` |
| Cancel in the host dialog | `Cancelled.` |

The host looks for the item only in the store of the same plugin. An item of another plugin counts as unknown.

## The host dialog

For an action with `confirm: true`, the app shows a native dialog before the action runs. The message is `<label>: <title>`. The title is the stored title of the item, or the plugin name for a plugin action. The first button has the label of the action. A `destructive` action marks that button as destructive. Return presses it, and Escape presses Cancel.

The dialog takes the label and the title from the host, not from the message. The page cannot turn the dialog off. Do not add a second dialog in the page.

## How an action runs

1. The host queues the action. The actions of a plugin run one after another, in one queue per plugin. A run of the plugin does not block the queue.
2. While the action waits or runs, the snapshot marks it as pending. `pending.items` holds the item id of an item action. `pending.plugin` is true for a plugin action.
3. The host sets the status to "Working on it…". For an item action, the status is the `status` of the item. For a plugin action, it is the `status` of the snapshot.
4. The handler returns `{ ok: true, value }` or `{ ok: false, error }`. The status becomes `value`, or `Error: <error>`.
5. The page gets the same answer. A thrown error or a timeout counts as a failure.

Each queued action writes a record and a log in Runs. If the plugin has a problem, for example a missing bundle, each action fails with the problem. An action also runs while the plugin is off in its Settings tab.

## What the handler checks

The host does not know the state of an item. The handler refuses an action that does not fit the item. For example, a plugin can refuse Close on a ticket that is already closed. It returns `{ ok: false, error }`, and the page gets that error.

```ts
import { definePlugin, err, moveCard, ok, onDoneAction } from "@routines/sdk";

definePlugin({
  onAction: async (event) => {
    if (event.actionId === "comment") return ok(`Noted: ${event.text}`);
    if (event.actionId !== "close") return onDoneAction(event);
    const moved = await moveCard(event.cardId, "done", "Closed.");
    if (!moved.ok) return moved;
    return moved.value ? ok("Closed.") : err("the ticket is gone or already closed");
  },
  onPluginAction: async ({ actionId, text }) => ok(`${actionId} ${text ?? ""}`.trim()),
});
```

`DONE_ACTION_ID` is `"done"`. `onDoneAction` handles the action `done` and moves the item to `done`. `moveCard(id, column, status?)` returns `false` for an item that is gone or that is already in the column.

## External actions

Another program runs `Routines --perform <plugin> <action> [text]`. The command opens `routines://perform?plugin=&action=&text=&reply=` in the running app, waits up to 120 seconds and prints the answer. If the answer starts with `Error`, it exits with 1. Otherwise it exits with 0.

The host runs only a plugin action that `permissions.external` lists. External actions do not go through the dialog, because nobody is at the Mac to answer it. The text check still applies.

| Call | Answer |
| --- | --- |
| A listed plugin action | The answer of the handler. A handler without an answer gives `Done.`. |
| A plugin that does not exist | `Error: the plugin <plugin> does not exist` |
| An action that `permissions.external` or the manifest does not list | `Error: denied: <plugin> does not allow <id> from outside the app` |
| An item action | `Error: denied: <id> needs an item` |
| A reply file outside the replies folder of the app | `Error: denied: the reply file must be in <folder>` |

## In the app

The app draws no action button, no action menu and no text field for actions. Each press comes from a plugin UI and goes through `ActionGate`. If another file of the app calls the actions of the host, `NativeActionsGoneTests` fails.
