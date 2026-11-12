# Data Model: Plugin UI in HTML and JavaScript

## Manifest

One field of `plugin.json` turns on the UI. The full contract is in [contracts/plugin-ui.md](contracts/plugin-ui.md).

| Field | Type | Rule |
| --- | --- | --- |
| `ui` | `{ title: string }` or absent | The plugin ships `dist/ui/index.html`. `title` is the label of its tab. |

With `ui`, the tabs of the plugin page are the UI, Runs and Settings. Without it, the tabs are Runs and Settings, under a banner. A plugin with `ui` and no `dist/ui/index.html` loads, and its UI tab shows the error.

## Action

Each entry of `actions` in the manifest. The full rules are in [the action contract](../003-custom-ui-everywhere/contracts/actions.md).

| Field | Type | Rule |
| --- | --- | --- |
| `id`, `label` | string | Required. The host finds an action by its `id`. |
| `style` | `primary`, `destructive`, `normal` or absent | The button variant. A destructive action also gets a destructive button in the host dialog. |
| `input` | `{ placeholder }` or absent | The action needs text that is not blank. |
| `confirm` | boolean or absent | With `true`, each press in the app shows the host dialog first. External actions show no dialog. |
| `target` | `item`, `plugin` or absent | `item` needs a stored item of the plugin. Absent means `plugin`. |

## Card (item)

The card of the plugin API, with one field for the UI. `column` is the state of the item: `planned`, `working`, `needs-you`, `done` or `failed`.

| Field | Type | Rule |
| --- | --- | --- |
| `data` | JSON object or absent | Opaque to the host. If it is larger than 32 KB as JSON, the upsert fails. Only the UI of the same plugin gets it. `activity.list` leaves it out. |

## Plugin UI snapshot

The value that the page gets from `snapshot` and from each `snapshot` event. `PluginUISnapshot.swift` builds it from the stores of one plugin.

| Field | Type | Source |
| --- | --- | --- |
| `plugin` | `{ id, name, emoji?, color }` | The manifest. |
| `items` | list of stored cards, each with `updatedAt` and `data` | The board store, this plugin only, newest `updatedAt` first. |
| `page` | `{ blocks, updatedAt }` or null | The page store. |
| `actions` | list of actions | `actions` of the manifest. |
| `pending` | `{ items: string[], plugin: boolean }` | The ids of the items with an action in flight, and whether a plugin action is in flight. |
| `status` | string or null | The answer of the last plugin action. |
| `appearance` | `{ scheme: "light" \| "dark", accent: "#RRGGBB" }` | The effective appearance and the accent color of the Mac. |

`page` and `status` are always present. A missing value is `null`.

## Bridge message and decision

`PluginWebView` first checks the frame. A message from a frame that is not the main frame, or from another origin than `routines-ui://<plugin id>`, is refused. A body that is not JSON is refused too. Then `PluginUIBridge` turns the message into one decision.

| Decision | Meaning | Answer to the page |
| --- | --- | --- |
| `reply(json)` | The answer to `snapshot`. | The snapshot. |
| `ready` | The page can show. The app shows the web view, sends the latest snapshot and sends a waiting `focus` event. | `null` |
| `refuse(reason)` | The host does nothing. | `{ ok: false, error: reason }` |
| `perform(action)` | `ActionGate` runs the manifest action. | The answer of the handler, or `null`. |
| `confirm(action, title)` | Like `perform`, but the gate shows the host dialog first. `title` is the stored card title, or the plugin name for a plugin action. | The answer of the handler, or `Cancelled.` as the error. |
| `open(url)` | The app opens the URL in the default browser. | `null` |

The action in a `perform` or `confirm` decision is the one in the manifest. Other fields of the message, for example `label` or `confirm`, change nothing.

Rules of the decision, each with a test in `PluginUIBridgeTests`:

1. A body that is not an object with a `type` is refused.
2. An unknown `type` is refused.
3. `perform` without `cardId` is refused. A message without `actionId` is refused.
4. An action id that the manifest does not list is refused.
5. `perform` of a plugin action and `performPluginAction` of an item action are refused.
6. A card id that the plugin does not have is refused.
7. An action with `input` and blank text is refused. Text with only white space is blank.
8. An action with `confirm: true` becomes `confirm`, never `perform`.
9. `openLink` with a URL that is not `http` or `https`, or that has no host, is refused.

## Scheme resource

`PluginUIResources` maps a URL of `routines-ui` to a file or a refusal.

| URL | Result |
| --- | --- |
| `routines-ui://<id>/` or `routines-ui://<id>/index.html` | `<plugin dir>/dist/ui/index.html` |
| `routines-ui://<id>/<path>` | The file under `<plugin dir>/dist/ui`, after the path resolves with symlinks. |
| `routines-ui://<id>/_image/<percent-encoded path>` | The file at the decoded absolute path. A stored card of plugin `<id>` must list that exact path in `images`. |
| Another scheme or another host | Refused. |

A file path is refused in these cases:

- It holds an encoded slash, backslash or NUL (`%2F`, `%5C` or `%00`).
- A part of it is empty, `.` or `..`.
- It resolves outside `dist/ui`.
- Its extension is not in the table below.
- It is a folder, or no file exists.

An image path is refused in these cases:

- No stored card of the plugin lists it.
- Its extension does not give an image type.
- No file exists.

| Extension | MIME type |
| --- | --- |
| `html` | `text/html` |
| `js` | `text/javascript` |
| `css` | `text/css` |
| `png` | `image/png` |
| `jpg`, `jpeg` | `image/jpeg` |
| `webp` | `image/webp` |
| `gif` | `image/gif` |
| `svg` | `image/svg+xml` |
| `woff2` | `font/woff2` |

A served file gets status 200. A refusal gets status 404 with an empty body. Each response carries `Content-Type`, `Content-Length`, `Cache-Control: no-store` and the content policy of [research.md](research.md), section 3.

## Host event

The host sends a `routines` event on `window`. `event.detail` holds `{ type, value }`.

| `type` | `value` |
| --- | --- |
| `snapshot` | The snapshot. |
| `focus` | `{ cardId }` |

## Design tokens

`design/tokens.json` holds the tokens in groups. The format is in [contracts/tokens.md](contracts/tokens.md). [DESIGN.md](../../DESIGN.md) lists each value and its use.

| Group | Tokens |
| --- | --- |
| `color` | `canvas`, `sidebar`, `column`, `column-border`, `card`, `card-border`, `pill`, `selection`, `text`, `muted`, `faint`, `danger`, `success`, `warning`, `on-accent` |
| `opacity` | `tint`, `pressed` |
| `font` | `display`, `title`, `heading-1`, `headline`, `heading-2`, `subhead`, `card-title`, `column-title`, `body-large`, `body`, `row-title`, `small`, `meta`, `button`, `caption`, `mono`, `label`, `micro` |
| `space` | `1`, `2`, `3`, `4`, `6`, `8`, `10`, `12`, `14`, `16`, `18`, `20`, `22`, `28` |
| `size` | `page-gutter`, `page-top`, `tab-min-width` |
| `padding` | `pill`, `button`, `field`, `tab` |
| `radius` | `card`, `sheet`, `panel`, `track`, `field`, `control` |
| `shadow` | `card`, `segment` |

The accent color is the accent color of the Mac, so it is not a token. The snapshot carries it.
