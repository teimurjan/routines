# Plugin UI contract

A plugin UI is a page that a plugin ships in `dist/ui`. The host shows it in the first tab of the plugin page. This contract adds to [plugin-api.md](../../001-swift-host/contracts/plugin-api.md). The actions follow [actions.md](../../003-custom-ui-everywhere/contracts/actions.md), and the look follows [DESIGN.md](../../../DESIGN.md).

## Folder

```text
plugins/<id>/
├── plugin.json        # with "ui": { "title": "Tickets" }
├── src/index.ts       # the plugin
├── ui/main.tsx        # the entry of the UI
├── ui/tsconfig.json   # the type check of the UI
└── dist/
    ├── plugin.js
    └── ui/            # index.html, ui.js, ui.css and the assets
```

## Build

In the workspace of the threads, `bun run build <id>` runs `scripts/build-plugins.ts`. In this repo, the script is `workspace/scripts/build-plugins.ts`. For a plugin with `ui/main.tsx`, the script does these steps:

1. It removes `dist/ui`.
2. It bundles `ui/main.tsx` for the browser as one classic script, with the JSX runtime of Preact.
3. It writes `dist/ui/ui.js` and `dist/ui/ui.css`. A UI without CSS gets an empty `ui.css`.
4. It writes each imported asset as `<name>-<hash>.<ext>`.
5. It writes `dist/ui/index.html` from a fixed shell.

The shell links `ui.css`, loads `ui.js` with `defer` and holds an empty `<div id="root">`. A plugin cannot add markup to it. A plugin repo of your own must write the same files. The host does not check the shell, but its content policy blocks inline script and remote files in any HTML.

After a change in `dist/` of a plugin in the workspace or in Application Support, the app loads the plugins again. A new `plugin.js` or `ui.js` then gives the open UI tab a new web view. For `ROUTINES_PLUGINS_DIR`, choose File > Reload Plugins.

## Manifest

```json
{
  "ui": { "title": "Tickets" },
  "actions": [
    { "id": "close", "label": "Close", "style": "destructive", "confirm": true, "target": "item" },
    { "id": "add", "label": "Add ticket", "style": "primary", "input": { "placeholder": "Title" } }
  ]
}
```

`ui.title` is the label of the UI tab. Runs and Settings follow it. The manifest lists each action, and a card has no actions.

## Limits of the page

The page runs in a web view with these limits:

| Limit | Rule |
| --- | --- |
| Origin | `routines-ui://<id>`. Each plugin has its own origin. |
| Storage | Each web view has its own store in memory. The store goes away with the web view, and the web view goes away with its tab. |
| Script | Only files of `dist/ui`. Inline script and event attributes in HTML do not run. |
| Style | Only files of `dist/ui`. A `<style>` element and a `style` attribute in markup do not apply. Script can still set `element.style`. |
| Network | None. `fetch`, `XMLHttpRequest`, WebSocket, remote images and remote fonts fail. |
| Navigation | None. The host cancels each load after the first load of `index.html`. `window.open` returns null. A link opens only through `openLink`. |
| Frames and forms | No frame loads, and no form submits to a URL. |
| Images | Files of `dist/ui`, and the image paths that the stored cards of the plugin list in `images`. |
| Messages | The host answers only the main frame of the page. |

The host serves only these file extensions: `html`, `js`, `css`, `png`, `jpg`, `jpeg`, `webp`, `gif`, `svg` and `woff2`. It refuses every other file type. The path rules are in [data-model.md](../data-model.md), section "Scheme resource".

## Messages from the page

The page sends a message with `window.webkit.messageHandlers.routines.postMessage(message)`. The promise resolves with `{ ok: true, value }` or `{ ok: false, error }`. Use the client of `@routines/ui`, and do not call `postMessage` yourself.

| `type` | Fields | Value |
| --- | --- | --- |
| `snapshot` | none | The snapshot. |
| `ready` | none | `null`. The host shows the web view after this message. Without it, the host shows the web view after 1 second. |
| `perform` | `cardId`, `actionId`, `text?` | An item action. The answer of `onAction`, or `null`. |
| `performPluginAction` | `actionId`, `text?` | A plugin action. The answer of `onPluginAction`, or `null`. |
| `openLink` | `url` | `null`. Only an `http` or `https` URL with a host opens, in the default browser. |

The host refuses an unknown `type`. For an action, it also refuses these calls:

- An action id that the manifest does not list.
- `perform` of a plugin action, or `performPluginAction` of an item action.
- `perform` with an item that the plugin does not have.
- An action with `input` and blank text.

[actions.md](../../003-custom-ui-everywhere/contracts/actions.md) lists the error text of each refusal.

For an action with `confirm: true`, the host shows its own dialog first. The promise resolves after the dialog. If you press Cancel, it resolves with `{ ok: false, error: "Cancelled." }`, and no handler runs.

## Events from the host

The host sends a `routines` event on `window`. `event.detail` holds `{ type, value }`.

| `type` | `value` | When |
| --- | --- | --- |
| `snapshot` | The snapshot. | After `ready`, at each change of the items, the page, the pending actions, the status or the appearance. |
| `focus` | `{ cardId }` | After `ready`, for each item that you open from the Inbox or from a notification. |

## Snapshot

```ts
type Snapshot = {
  plugin: { id: string; name: string; emoji?: string; color: string };
  // The stored cards of this plugin, newest updatedAt first.
  items: StoredCard[];
  page: Page | null;
  // The actions of the manifest.
  actions: CardAction[];
  // The ids of the items with an action in flight, and whether a plugin action is in flight.
  pending: { items: string[]; plugin: boolean };
  // The answer of the last plugin action.
  status: string | null;
  appearance: { scheme: "light" | "dark"; accent: string };
};
```

`StoredCard`, `Page` and `CardAction` are the types of `@routines/sdk`. `accent` is the accent color of the Mac as `#RRGGBB`.

## The client in `@routines/ui`

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

| Export | What it does |
| --- | --- |
| `mount(App)` | Renders `App` on `#root` inside `PluginProvider`, after the first snapshot. If the first snapshot fails, it shows the error. |
| `PluginProvider` | Asks for the first snapshot, sends `ready` once, follows the `snapshot` events and sets `--accent` from the appearance. |
| `usePlugin()` | The snapshot, `perform`, `performPluginAction`, `openLink` and `isPending`. |
| `useSnapshot()` | The snapshot alone, inside `mount`. |
| `isPending(cardId?)` | With an id, true while an action of the item runs. Without an id, true while a plugin action runs. |
| `useFocus(handler)` | Calls the handler with the item id of each `focus` event. |
| `useFocusedItem(onFocus?)` | The id of the last focused item. The page scrolls to the element with that id. |
| `imageUrl(path)` | The URL of an image path from `images`. |
| `actionOf(snapshot, id)` | The manifest action with that id, or `undefined`. |
| `bridge`, `connect`, `onHostEvent` | The raw client. Each call resolves with a `Result` and does not throw. |

Outside the app, each call of the client fails with the error "the page runs outside the Routines app". The controls, for example `ActionButton`, `ItemBoard` and `Markdown`, are in [ui-controls.md](../../003-custom-ui-everywhere/contracts/ui-controls.md) and [DESIGN.md](../../../DESIGN.md).

## Rules for a plugin UI

1. Show text from items as text. JSX escapes text. No UI code inserts HTML. If a file in `packages/ui/src` contains `dangerouslySetInnerHTML` or `innerHTML`, `scripts/no-html.test.ts` fails. A plugin repo can keep the same test for its UIs.
2. Use the controls and the tokens of `@routines/ui`. Do not set a color, a font size or a radius as a literal.
3. Keep no state that the host does not have. A new web view shows the same page.
4. Leave the dialog to the host. Do not add a second dialog for an action with `confirm: true`.
5. Give each keyboard key a visible button with the same action and label.
6. Take each action from the manifest. `ActionButton` reads its label and style there, so the button and the host dialog use the same words.
