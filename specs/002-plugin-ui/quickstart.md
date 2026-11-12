# Quickstart: Plugin UI in HTML and JavaScript

These steps prove that the feature works from end to end. Run them from the root of the checkout, with Bun 1.3 and Xcode with Swift 6.

## 1. Run the tests

```sh
bun install
bun run tokens --check
bun test packages scripts
cd app && swift test
```

Expected result:

- The token outputs match `design/tokens.json`.
- `bun test` passes the tests of the bridge client, the Markdown parser, the item groups, the token build and the HTML rule.
- `swift test` passes `PluginUIManifestTests`, `PluginUIResourcesTests`, `PluginUIBridgeTests`, `ActionLookupTests`, `TokenUseTests`, `NativeActionsGoneTests` and `HostIsGenericTests`.

The bridge and resource tests load the fixture `app/Tests/RoutinesKitTests/Fixtures/ui-plugin`.

## 2. Run the WebKit security test

This test opens a real web view, so it runs only on your request.

```sh
cd app && ROUTINES_WEBKIT_TESTS=1 swift test --filter PluginUIWebKitTests
```

Expected result: the page of `Fixtures/hostile-ui` fails at each of its seven tries. See [research.md](research.md), section 11.

## 3. Make a small plugin with a UI

This plugin lists open tickets. A plugin action adds a ticket, and an item action closes it after the host dialog.

1. Build the workspace source and start the app with an empty data folder:

   ```sh
   bun run build
   cd app && ROUTINES_DATA_DIR="$HOME/routines-ui-check" ROUTINES_WORKSPACE_SOURCE="$PWD/../build/workspace" swift run Routines
   ```

2. In a second terminal, make the plugin folder:

   ```sh
   mkdir -p ~/routines-ui-check/workspace/plugins/tickets/src ~/routines-ui-check/workspace/plugins/tickets/ui
   cd ~/routines-ui-check/workspace/plugins/tickets
   ```

3. Write `plugin.json`:

   ```json
   {
     "id": "tickets",
     "name": "Tickets",
     "description": "Lists open tickets.",
     "ui": { "title": "Tickets" },
     "actions": [
       { "id": "add", "label": "Add ticket", "style": "primary", "input": { "placeholder": "Title" } },
       { "id": "close", "label": "Close", "style": "destructive", "confirm": true, "target": "item" }
     ]
   }
   ```

4. Write `src/index.ts`:

   ```ts
   import { definePlugin, host, moveCard, ok } from "@routines/sdk";

   definePlugin({
     onPluginAction: async ({ text }) => {
       const title = text?.trim() ?? "";
       const added = await host().board.upsert({ id: crypto.randomUUID(), title, column: "needs-you" });
       return added.ok ? ok(`Added ${title}.`) : added;
     },
     onAction: async ({ cardId }) => {
       const moved = await moveCard(cardId, "done");
       return moved.ok ? ok("Closed.") : moved;
     },
   });
   ```

5. Write `ui/main.tsx`:

   ```tsx
   import { ActionButton, ItemBoard, mount, useSnapshot } from "@routines/ui";

   const App = () => (
     <main class="rt-page">
       <div class="rt-toolbar">
         <ActionButton actionId="add" />
       </div>
       <ItemBoard items={useSnapshot().items} empty="No ticket is open." actions={(item) => <ActionButton actionId="close" cardId={item.id} />} />
     </main>
   );

   mount(App);
   ```

6. Build the plugin in the workspace:

   ```sh
   cd ~/routines-ui-check/workspace && bun run build tickets
   ```

Expected result: `plugins/tickets/dist/ui` holds `index.html`, `ui.js` and `ui.css`. `index.html` is the fixed shell of `scripts/build-plugins.ts`. Tickets shows in the sidebar of the app without a restart.

## 4. Open the UI

1. Select Tickets in the sidebar. The first tab is Tickets, then Runs and Settings. No white frame shows.
2. Put the Inbox and Tickets side by side. The backgrounds have the same color.
3. Switch the Mac between light and dark mode in System Settings. The UI and the app change together.
4. Change the accent color of the Mac. The Add ticket button changes to the new color.

## 5. Act from the UI

1. Leave the Add ticket field blank. The button stays disabled.
2. Type "Printer is down" and press Add ticket. A Needs you column shows the ticket, and no reload happens.
3. Press the ticket, then press Close. The host dialog shows "Close: Printer is down".
4. Press Cancel. The ticket stays, and no error shows.
5. Press Close again, then press Return. The ticket moves to Done, with the status "Closed.".

## 6. Open an item from the Inbox

1. Add a second ticket.
2. Open the Inbox. It lists the new ticket with the Tickets mark.
3. Press the row. The app opens Tickets, and the UI opens the detail of that ticket.

## 7. The design rules

1. Change `canvas` in `design/tokens.json`, then run `bun run tokens`. `Tokens.swift` and `packages/ui/src/tokens.css` hold the new value. Undo the change and run `bun run tokens` again.
2. Add `.font(.system(size: 13))` to a view in `app/Sources/Routines/Views`, then run `cd app && swift test --filter TokenUseTests`. The test fails. Remove the line.
3. Read `DESIGN.md`. Each token of `design/tokens.json` has an entry with its use.

## 8. Clean up

Quit the app and delete the folder `~/routines-ui-check`.
