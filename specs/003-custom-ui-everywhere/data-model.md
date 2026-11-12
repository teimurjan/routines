# Data Model: Plugin UIs and manifest actions

This feature defines the plugin action, the item without actions, the tabs of a plugin page and the decision rules of the bridge. The snapshot, the scheme and the bridge messages are in [the data model of 002](../002-plugin-ui/data-model.md).

## Plugin action

One entry of `actions` in `plugin.json`. It is the only list of actions of a plugin. Swift: `CardAction` in `Model/Card.swift`. TypeScript: `CardAction` in `packages/sdk/src/host.ts`.

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | The id that the page sends and that the handler gets. |
| `label` | string | The button label in the UI and the action name in the host dialog. |
| `style` | `"primary"`, `"destructive"` or `"normal"`, or absent | The variant of the button. A `destructive` action also marks the dialog button as destructive. |
| `input` | `{ placeholder }` or absent | With it, the action needs text that is not blank. |
| `confirm` | boolean or absent | With `true`, each press in the app shows the host dialog first. |
| `target` | `"item"` or `"plugin"`, or absent | Absent means `"plugin"`. An item action needs an item of the plugin. A plugin action takes no item. |

`permissions.external` lists the ids of plugin actions that another program can start.

## Item

One card of a plugin. Swift: `Card`. TypeScript: `Card`, and `StoredCard` with `updatedAt`. The plugin owns each field but `updatedAt`.

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | Unique in the plugin. |
| `title` | string | The title in the Inbox, on a board card and in the host dialog. |
| `body` | Markdown or absent | A UI draws it with `Markdown`. |
| `column` | `planned`, `working`, `needs-you`, `done` or `failed` | The state. The Inbox lists the items in `needs-you`. |
| `progress` | number from 0 to 1, or absent | A UI draws it with `ProgressRing`. |
| `date` | ISO 8601 or absent | The date of the item. Without it, a UI shows `updatedAt`. |
| `tags` | strings or absent | A UI draws them as pills. |
| `links` | `{ label, url }[]` or absent | Each link opens through `openLink`. |
| `images` | absolute paths or absent | The scheme serves only the images that a card of the plugin lists. |
| `status` | string or absent | One line under the body. The host writes the answer of the last item action here. |
| `data` | JSON object or absent | Fields for the UI of the plugin, up to 32 KB as JSON. The host stores them and does not read them. |
| `updatedAt` | ISO 8601 | The host sets it at each upsert. |

An item has no `actions` field. The decoder ignores an `actions` key in a stored file, and the next save drops it.

## Tabs of a plugin page

| Manifest | Tabs | First tab |
| --- | --- | --- |
| With `ui` | UI (labeled `ui.title`), Runs, Settings | UI |
| Without `ui` | Runs, Settings, under a banner that says that the plugin has no UI | Runs |

## Bridge decision rules

`PluginUIBridge.decide` turns one page message into one decision. Each rule has a test in `PluginUIBridgeTests`.

1. A body that is not an object with `type` is refused.
2. A message with an unknown `type` is refused.
3. A `perform` without `cardId`, or a `perform` or `performPluginAction` without `actionId`, is refused.
4. An action id that the manifest does not list is refused.
5. A `perform` of a plugin action, or a `performPluginAction` of an item action, is refused.
6. A `perform` with a card id that the plugin does not have is refused.
7. An action with `input` and no text or blank text is refused.
8. An action with `confirm: true` becomes `confirm`. The title is the stored item title for an item action and the plugin name for a plugin action.
9. Any other listed action becomes `perform`.
10. An `openLink` URL with a scheme other than `http` or `https`, or without a host, is refused.

## Action answer

| Moment | Item action | Plugin action |
| --- | --- | --- |
| While it runs | The `status` of the item is "Working on it…". | The `status` of the snapshot is "Working on it…". |
| After success | The `status` of the item is the answer of the handler. | The `status` of the snapshot is the answer of the handler. |
| After failure | The `status` of the item is `Error: <reason>`. | The `status` of the snapshot is `Error: <reason>`. |
| In flight | `pending.items` holds the item id. | `pending.plugin` is true. |

## Markdown node

The parser in `packages/ui/src/markdown.ts` returns these nodes. The `Markdown` control draws each one as an element, never as HTML.

`parseMarkdown(text)` reads the text line by line. Each line that is not blank becomes one block. A fence line starts or ends one code block.

| Block | Source | Fields |
| --- | --- | --- |
| `heading` | `#` to `######` and a space. A deeper heading counts as level 3. | `level` from 1 to 3, `inline` |
| `item` | `-`, `*`, `+` or a number and a dot, then a space | `inline` |
| `paragraph` | Any other line | `inline` |
| `code` | The lines between two fences of three backticks | `text`: the lines as they are. A fence without its end runs to the end of the text. |

`parseInline(text)` returns the inline nodes of one line.

| Inline | Source | Fields |
| --- | --- | --- |
| `text` | Plain text. A backslash escape becomes the next character as text. | `text` |
| `strong` | `**text**` | `children` |
| `emphasis` | `*text*` or `_text_`, not inside a word | `children` |
| `code` | `` `text` `` | `text` |
| `link` | `[label](url)` | `children` and `url`. A URL that is not `http` or `https` becomes its label as text. |

HTML in the text stays text. Next text nodes merge into one.

## Item groups

`byState(items)` returns the groups in this order, each newest first by `updatedAt`: `needs-you`, `working`, `planned`, `failed` and `done`. A group with no items is left out. `STATE_ORDER`, `STATE_TITLES` and `STATE_TONES` in `packages/ui/src/groups.ts` hold the order, the titles and the dot colors.

| State | Title | Tone |
| --- | --- | --- |
| `needs-you` | Needs you | `accent` |
| `working` | In progress | `warning` |
| `planned` | Planned | `neutral` |
| `failed` | Failed | `danger` |
| `done` | Done | `success` |
