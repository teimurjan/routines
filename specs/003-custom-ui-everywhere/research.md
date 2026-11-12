# Research: Plugin UIs and manifest actions

Each section names a decision, the reason for it and the other options. The security rules of a plugin UI are in [research.md of 002](../002-plugin-ui/research.md).

## 1. The target of an action

Decision: each entry of `actions` in the manifest has an optional `target`, with the value `item` or `plugin`. Without `target`, an action is a plugin action. The page message `perform` calls an item action and needs a `cardId`. The message `performPluginAction` calls a plugin action and has no `cardId`.

Rationale: the host must refuse an item action without an item and a plugin action with one. One field in the manifest makes this a lookup. The default keeps a short manifest for a plugin with only plugin actions.

Alternatives considered: two lists, `actions` and `itemActions`. They split one concept, and one id can then be in both. An action without a target, which the plugin checks itself. The host check then depends on each handler.

## 2. What the host checks and what the plugin checks

Decision: `ActionLookup` finds the action by its id in the manifest. It refuses an unknown id, a wrong target and an item that the plugin does not have. `ActionLookup.checkText` refuses an action with `input` and blank text. The handler of the plugin checks that the action fits the state of the item. For a bad fit, it returns `{ ok: false, error }`.

Rationale: only the plugin knows the state of its items. The column of an item is not always its state. A plugin can keep a status in `data` or in a state file.

Alternatives considered: a list of allowed columns per action in the manifest. It copies the state rules of each plugin into JSON, and it fails for a state that is not a column.

## 3. Items carry no actions

Decision: `Card` has no `actions` field in Swift or in `packages/sdk`. The Swift decoder ignores an `actions` key, so a stored file with the key loads. The next save drops it. The SDK gives `DONE_ACTION_ID` and `onDoneAction` for the common item action `{ "id": "done", "label": "Done", "target": "item" }`.

Rationale: one list of actions per plugin. A reader of a card does not need to ask which list counts.

Alternatives considered: actions on each card, with the manifest as a second list. Two lists can disagree, and the host then needs a rule for each conflict.

## 4. The tabs of a plugin page

Decision: if the manifest has `ui`, `PluginTab.tabs(of:)` returns the UI tab, then Runs and Settings. Without `ui`, it returns Runs and Settings. The UI tab takes its label from `ui.title`. A manifest without `ui` shows a banner and opens on Runs.

Rationale: one fixed tab list keeps the view logic out of the manifest.

Alternatives considered: a list of views in the manifest. A field with one useful value is noise.

## 5. One gate in the app

Decision: `ActionGate.run` is the only app code that calls `host.perform` or `host.performPluginAction`. `PluginUIController` sends each `perform` and `confirm` decision of the bridge to it. `NativeActionsGoneTests` scans `app/Sources/Routines`. If another file calls one of the two functions, the test fails. If a file names an action control, a board view or a card detail, it also fails.

Rationale: the dialog and the checks then run for each press. A new view cannot skip them by mistake.

Alternatives considered: a check in each view. Each new view then needs its own test.

## 6. The dialog

Decision: the dialog is an `NSAlert` sheet on the key window, or a modal alert without a window. Its message is `<label>: <title>`. The title is the stored item title for an item action and the plugin name for a plugin action. The first button has the label of the action, and a `destructive` action marks it as destructive. Return presses it, and Escape presses Cancel. Cancel returns the error `Cancelled.`.

Rationale: the host takes the label and the title from its own stores, so a page cannot show a harmless text for a harmful action.

Alternatives considered: a dialog in the page. The page then controls what you see, and a hostile page can skip it.

## 7. The answer of an action

Decision: the host runs the actions of a plugin one after another, in one queue per plugin. A run does not block the queue. While an action runs, the host sets the status to "Working on it…". For an item action, the status is the `status` of the item. For a plugin action, it is the `status` of the snapshot. When the action ends, the status is the answer of the handler, or `Error: <reason>`.

Rationale: the page needs no own state for an answer. The snapshot carries it, so a reload shows the same page.

## 8. Pending presses

Decision: the snapshot lists the items with an action in flight and a flag for the plugin queue. `usePlugin().isPending` also counts a press that waits for the dialog or for the queue. `ActionButton` is disabled while its action is pending.

Rationale: a second press cannot start the same action twice before the host queues the first one.

## 9. Shared controls in `packages/ui`

Decision: the controls that three or more UIs need live in `packages/ui`.

| Control | What it does |
| --- | --- |
| `markdown.ts` | A pure parser of the Markdown that plugins write. It returns a tree of nodes, not HTML. |
| `Markdown` | Draws the tree as Preact elements. A link is a button that calls `openLink`. |
| `ActionButton` | Draws a manifest action with its label, its style and its input. It calls `perform` or `performPluginAction`. |
| `ItemBoard`, `ItemTile`, `ItemDetail` | Draw stored items as a board, a compact card and a full detail. |
| `byState` | Groups items by state, what needs you first. |
| `PageBlocks` | Draws the blocks of `page.publish`. |

Rationale: item bodies are Markdown that `escapeMarkdown` made safe, so a UI needs one safe way to show them. One `ActionButton` keeps each label and style the same as in the manifest and in the host dialog.

Alternatives considered: a Markdown library such as `marked`. It returns HTML, which rule 1 of the plugin UI contract forbids. A generic UI that the host gives to each plugin. One view does not fit each routine.

## 10. Page blocks as data

Decision: the page store and `page.publish` hold blocks of Markdown and status. The snapshot carries `page`, and the app does not draw it. A UI draws it with `PageBlocks`, or with `Markdown` and `Status`.

Rationale: a plugin can publish a report or a status without the shape of an item. The data is already in the snapshot.

Alternatives considered: a card that carries the report in `data`. It then shows in the Inbox logic and falls under the retention rules.

## 11. The Inbox and the focus

Decision: an Inbox row and a notification call `AppModel.open(pluginId:cardId:)`. It selects the plugin and its first tab. For a plugin with `ui`, it sets `uiFocus`. `PluginUIController` sends the `focus` event after `ready`. `useFocusedItem` gives the id to the page and scrolls the element with that id into view.

Rationale: one path serves the Inbox and the notifications. A click before the page loads still reaches the page.

## 12. External actions

Decision: `ExternalAction.check` allows only an action that `permissions.external` lists and that the manifest has. It refuses an item action, and it refuses a reply file outside the replies folder of the app. `PluginHost.performExternal` then calls `performPluginAction` without `ActionGate`.

Rationale: an external call has no item and nobody at the Mac to answer a dialog. The manifest list is the consent.

## 13. Tests of the rules

Decision: `ActionLookupTests` covers the refusals of the host with no run record and no pending action. `PluginUIBridgeTests` covers the decision for each message. `ExternalActionTests` covers the external rules. `NativeActionsGoneTests` covers the gate. `packages/ui` has tests of the Markdown parser, `byState`, the bridge client and `actionOf`. `scripts/no-html.test.ts` fails on an HTML sink in `packages/ui/src`.

Rationale: one named test per rule, as the constitution asks.
