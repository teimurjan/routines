# Quickstart: Plugin UIs and manifest actions

These steps prove that the feature works from end to end. Run each command from the root of the checkout. You need Bun 1.3 and Xcode with Swift 6.

## 1. Run the tests

```sh
bun install
bun test packages scripts
bun run app:test
```

Expected result: all tests pass. `bun test` runs the tests of the Markdown parser, `byState`, the bridge client and the HTML check. `bun run app:test` builds the prelude and runs `swift test` in `app`.

## 2. Run the action tests alone

```sh
swift test --package-path app --filter "ActionLookupTests|PluginUIBridgeTests|ExternalActionTests|NativeActionsGoneTests"
```

Expected result: each suite passes.

| Suite | What it proves |
| --- | --- |
| `ActionLookupTests` | The host refuses an unlisted id, a wrong target, an unknown item and blank text. No run record and no pending action stay. |
| `PluginUIBridgeTests` | Each page message gets the right decision. A marked action asks first with the stored title. |
| `ExternalActionTests` | Another program starts only a listed plugin action. |
| `NativeActionsGoneTests` | Only `ActionGate.swift` calls the actions of the host. |

The tests use the fixtures in `app/Tests/RoutinesKitTests/Fixtures`.

## 3. Run the WebKit security test

This test opens a real web view, so it runs only on request.

```sh
ROUTINES_WEBKIT_TESTS=1 swift test --package-path app --filter PluginUIWebKitTests
```

Expected result: the page of the fixture `hostile-ui` fails at each try. Its call of an unlisted action fails too.

## 4. Make a small plugin

Copy the workspace of the threads to a test folder:

```sh
bun run build:workspace
rm -rf /tmp/routines-try && mkdir -p /tmp/routines-try/data
cp -R build/workspace /tmp/routines-try/workspace
mkdir -p /tmp/routines-try/workspace/plugins/tickets/src /tmp/routines-try/workspace/plugins/tickets/ui
```

Write `/tmp/routines-try/workspace/plugins/tickets/plugin.json`:

```json
{
  "id": "tickets",
  "name": "Tickets",
  "description": "Lists the open tickets.",
  "emoji": "🎫",
  "runAtLaunch": true,
  "timeoutMinutes": 1,
  "ui": { "title": "Tickets" },
  "actions": [
    { "id": "done", "label": "Done", "target": "item" },
    { "id": "close", "label": "Close", "style": "destructive", "confirm": true, "target": "item" },
    { "id": "add", "label": "Add", "style": "primary", "input": { "placeholder": "A ticket title" } }
  ],
  "permissions": { "external": ["add"] }
}
```

Write `/tmp/routines-try/workspace/plugins/tickets/src/index.ts`:

```ts
import { definePlugin, moveCard, ok, onDoneAction } from "@routines/sdk";

const body = "Read **the guide** at [example.com](https://example.com).";

definePlugin({
  run: async () => {
    const added = await routines.board.upsert({ id: "t1", title: "First ticket", body, column: "needs-you" });
    return added.ok ? ok("Added the first ticket.") : added;
  },
  onAction: async (event) => {
    if (event.actionId !== "close") return onDoneAction(event);
    const moved = await moveCard(event.cardId, "done");
    return moved.ok ? ok("Closed.") : moved;
  },
  onPluginAction: async ({ text }) => {
    const added = await routines.board.upsert({ id: `t${Date.now()}`, title: text ?? "", column: "needs-you" });
    return added.ok ? ok("Added.") : added;
  },
});
```

Write `/tmp/routines-try/workspace/plugins/tickets/ui/main.tsx`:

```tsx
import { ActionButton, DoneButton, ItemBoard, mount, useSnapshot } from "@routines/ui";

const App = () => {
  const { items, status } = useSnapshot();
  return (
    <div class="rt-page">
      <div class="rt-toolbar">
        <ActionButton actionId="add" />
      </div>
      {status && <p class="rt-note">{status}</p>}
      <ItemBoard
        items={items}
        empty="No ticket is open."
        actions={(item) => (
          <>
            <DoneButton item={item} />
            <ActionButton actionId="close" cardId={item.id} />
          </>
        )}
      />
    </div>
  );
};

mount(App);
```

Build the plugin:

```sh
(cd /tmp/routines-try/workspace && bun run build tickets)
```

Expected result: the build writes `dist/plugin.js` and `dist/ui/index.html` in the plugin folder.

## 5. Use the app

Run the app with the test folders:

```sh
ROUTINES_PLUGINS_DIR=/tmp/routines-try/workspace/plugins ROUTINES_DATA_DIR=/tmp/routines-try/data ROUTINES_WORKSPACE_SOURCE="$PWD/build/workspace" swift run --package-path app Routines
```

1. Open Tickets in the sidebar. The tabs are Tickets, Runs and Settings.
2. The board shows "First ticket" in Needs you. The Inbox count is 1.
3. Press the card. The detail pane shows the body with bold text and a link, and the buttons Done and Close.
4. Press the link. The page opens in the default browser.
5. Press Close. The dialog shows "Close: First ticket". Press Cancel. The item stays, and Runs lists no action.
6. Press Close again, and press Close in the dialog. The item moves to Done.
7. Look at the Add field. While the field is blank, Add is disabled.
8. Type "Second ticket" in the field and press Return. The new item shows in Needs you, and the note shows "Added.".
9. Open the Inbox and click the row of "Second ticket". The app opens Tickets, and the detail pane shows the item.
10. Type "second" in the Inbox search field. Only that row stays.

## 6. External actions

The `routines://` URL scheme works only in the bundled app. Quit the app of step 5 and any other copy of Routines. Then build the bundle and start it:

```sh
bun run app:bundle
ROUTINES_PLUGINS_DIR=/tmp/routines-try/workspace/plugins ROUTINES_DATA_DIR=/tmp/routines-try/data build/Routines.app/Contents/MacOS/Routines
```

In a second terminal, run these commands from the root of the checkout:

```sh
ROUTINES_DATA_DIR=/tmp/routines-try/data build/Routines.app/Contents/MacOS/Routines --perform tickets add "From outside"
ROUTINES_DATA_DIR=/tmp/routines-try/data build/Routines.app/Contents/MacOS/Routines --perform tickets done
```

Expected result:

1. The first command prints "Added." and exits with 0. No dialog shows, and "From outside" shows in Needs you.
2. The second command prints `Error: denied: tickets does not allow done from outside the app` and exits with 1.

## 7. Clean up

```sh
rm -rf /tmp/routines-try
```
