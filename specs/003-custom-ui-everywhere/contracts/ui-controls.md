# UI control contract

`@routines/ui` is the package that each plugin UI imports. It gives the bridge client, the hooks, the controls and the CSS of the app. [DESIGN.md](../../../DESIGN.md) describes the look of each control with an example. [The plugin UI contract](../../002-plugin-ui/contracts/plugin-ui.md) describes the messages and the events of the bridge.

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
      <ItemBoard items={items} empty="No ticket is open." actions={(item) => <DoneButton item={item} />} />
    </div>
  );
};

mount(App);
```

The import also loads the CSS of the package, so the page gets the tokens and the styles of each control.

## Page and state

| Export | Shape | Rule |
| --- | --- | --- |
| `mount(App)` | `(App: ComponentType) => void` | Renders `App` on `#root` inside `PluginProvider`. It renders nothing until the first snapshot. If the first snapshot fails, it shows the error. |
| `PluginProvider` | `{ children }` | Holds the one connection of the page to the host. `mount` adds it. |
| `usePlugin()` | `() => PluginState` | The state of the provider. It throws outside `PluginProvider`. |
| `useSnapshot()` | `() => Snapshot` | The current snapshot. It throws outside `mount`. |
| `PluginState` | type | `{ snapshot, error, perform, performPluginAction, openLink, isPending }`. |
| `isPending(cardId?)` | `(cardId?: string) => boolean` | With an id, true while an action of that item waits or runs. Without an id, true while a plugin action waits or runs. A press that waits for the dialog counts. |
| `useFocus(handler)` | `(handler: (cardId: string) => void) => void` | Calls the handler on each `focus` event of the host. |
| `useFocusedItem(onFocus?)` | `(onFocus?: (cardId: string) => void) => string \| undefined` | The id of the item that a notification or an Inbox row asked for. It calls `onFocus`, then scrolls the element with that id into view. |

## Bridge client

| Export | Shape | Rule |
| --- | --- | --- |
| `bridge` | object | `ready()`, `snapshot()`, `perform(cardId, actionId, text?)`, `performPluginAction(actionId, text?)` and `openLink(url)`. Each call resolves with a `Result`. |
| `connect(onSnapshot, onError)` | `(...) => () => void` | Gets the first snapshot, follows each new one and sends `ready`. It returns the function that stops it. `PluginProvider` calls it. |
| `onHostEvent(listener)` | `(listener: (event: HostEvent) => void) => () => void` | Calls the listener on each `snapshot` and `focus` event. It returns the function that stops it. |
| `actionOf(snapshot, actionId)` | `(snapshot?: Snapshot, actionId: string) => CardAction \| undefined` | Pure. The manifest action with this id. |
| `imageUrl(path)` | `(path: string) => string` | The scheme URL of an image path that a card of the plugin lists in `images`. |
| `Snapshot`, `HostEvent` | types | The snapshot and the events of the host. |

Outside the app, each call fails with "the page runs outside the Routines app". A reply that is not a `Result` fails with "the host sent no result".

## Actions

| Export | Props | Rule |
| --- | --- | --- |
| `ActionButton` | `{ actionId: string; cardId?: string; shortcut?: string; onResult?: (result) => void }` | See below. |
| `DoneButton` | `{ item: StoredCard }` | The item action `done` as an `ActionButton`. It draws nothing for an item that is not in `needs-you`. |

`ActionButton` reads the label, the style, the input and the target of the action from `snapshot.actions`:

1. With `cardId`, it runs an item action through `perform`. Without `cardId`, it runs a plugin action through `performPluginAction`.
2. If the manifest does not list the id, it draws nothing. If the target of the action does not match `cardId`, it also draws nothing.
3. An action with `input` shows a field with the placeholder and a button with the label. Return in the field presses the button. The button stays disabled while the field is blank. After a success, the field clears.
4. While the action is pending, the button is disabled.
5. An error shows under the button. `Cancelled.` shows no error.
6. `onResult` gets the result of each press.
7. `shortcut` shows the key on the button. The page binds the key itself.

## Content

| Export | Props or shape | Rule |
| --- | --- | --- |
| `Markdown` | `{ text: string }` | Draws the blocks of `parseMarkdown` as elements. A heading is `h2` to `h4`. A link is a button that calls `openLink`. |
| `parseMarkdown(text)` | `(text: string) => Block[]` | Pure. See "Markdown node" in [data-model.md](../data-model.md). |
| `parseInline(text)` | `(text: string) => Inline[]` | Pure. The inline nodes of one line. |
| `previewOf(text)` | `(text: string) => string` | Pure. The plain text of the first block that is not code. |
| `Block`, `Inline` | types | The nodes of the parser. |
| `PageBlocks` | `{ page: Page \| null; empty: string }` | The blocks of `page.publish`, under "Updated" and the time of their last change. Next status blocks show as one grid. Next Markdown blocks show as one flow. With no page, it shows `empty`. |
| `Status` | `{ state: "ok" \| "warning" \| "error" \| "neutral"; label: string; detail?: string }` | A dot, a label and an optional detail. |

## Items

| Export | Props or shape | Rule |
| --- | --- | --- |
| `ItemBoard` | `{ items; empty; columns?; actions?; quickActions?; leading?; sort? }` | See below. |
| `ItemTile` | `{ item; selected; onOpen; leading?; footer? }` | The `BoardCard` of an item. Its element id is the item id. If the status starts with "Error", the preview is the status. Otherwise it is `previewOf(body)`. The meta row shows two tags, the progress and `timeAgo`. |
| `ItemDetail` | `{ item: StoredCard; children? }` | The first image, the state, the date, the tags, the progress, the status, `children` as the actions, the links and the body as `Markdown`. |
| `byState(items)` | `(items: StoredCard[]) => { state: Column; items: StoredCard[] }[]` | Pure. See "Item groups" in [data-model.md](../data-model.md). |
| `newestFirst` | `(left: StoredCard, right: StoredCard) => number` | Pure. Sorts by `updatedAt`, newest first. |
| `STATE_ORDER`, `STATE_TITLES`, `STATE_TONES` | constants | The order, the titles and the tones of the states. |
| `Tone` | type | `accent`, `warning`, `danger`, `success` or `neutral`. |

`ItemBoard` draws the items as a `Board`:

1. With no items, it shows `empty`.
2. By default, it shows one column per state that has items, in the order of `byState`. `columns(items)` gives other columns.
3. `sort` orders the items in each column.
4. A press on a card opens its `ItemDetail` in a `DetailPane`. A second press on the same card closes it.
5. A `focus` event of the host opens the detail of that item.
6. `actions(item)` gives the buttons of the detail. `quickActions(item)` gives the buttons on the card. `leading(item)` gives a short mark before the title.

## Layout

| Export | Props | Rule |
| --- | --- | --- |
| `PageHeader` | `{ trail: string[]; title: string; subtitle?: string; children? }` | The breadcrumb, the title and the subtitle. `children` go on the right. |
| `TabStrip` | `{ tabs: { id; label }[]; selected; onSelect }` | A segmented control. |
| `SearchField` | `{ value: string; onInput: (value: string) => void; placeholder?: string }` | A search field with a clear button. |
| `Board` | `{ columns: BoardColumn[]; keyOf; renderItem; empty? }` | The columns side by side. A column without items shows `empty`, by default "Nothing here.". |
| `BoardColumn` | type | `{ id, title, tone?, items }`. |
| `BoardCard` | `{ id?; title; leading?; preview?; meta?; footer?; selected?; unread?; dense?; onOpen? }` | A compact card. A press or the Return key calls `onOpen`. A press in `footer` does not. |
| `Workspace` | `{ detail?; children }` | The main view. If `detail` is set, the detail shows at its right side. |
| `DetailPane` | `{ title: string; onClose: () => void; children }` | A side panel. Escape and the close button call `onClose`. Escape in a field does not. |
| `Card` | `{ title; body?; status?; meta?; footer?; selected?; onClick? }` | A card. The body is plain text. A status that starts with "Error" shows as an error. |
| `Button` | `{ variant?; disabled?; shortcut?; onClick; children }` | `variant` is `primary`, `destructive` or `normal`. `shortcut` shows a key. |
| `Pill` | `{ children }` | A small label. |
| `ProgressRing` | `{ value: number }` | A ring for a value from 0 to 1. |
| `progressTone(value)` | `(value: number) => "faint" \| "warning" \| "success"` | Pure. `faint` below 0.01, `warning` below 0.6, `success` from 0.6. |

## Format

| Export | Shape | Rule |
| --- | --- | --- |
| `timeAgo(iso, now?)` | `(iso: string, now?: Date) => string` | Pure. "now", then minutes, hours or days for the last week, for example "5m", "3h" and "6d". An older time shows its day. A bad time gives "". |
| `shortDay(iso)` | `(iso: string) => string` | The month and the day, for example "Nov 9". |

## CSS classes

| Class | Use |
| --- | --- |
| `rt-page` | The page, with the page gutter on each side. |
| `rt-toolbar` | A row of plugin actions above the content. `rt-toolbar__spacer` pushes the next controls to the right. |
| `rt-note` | One line of muted text, for example the answer of the last action. |
| `rt-empty` | The text of an empty list. |
| `rt-stack` | A column of blocks with a gap. |
| `rt-field` | A text field. |
| `rt-link` | A text button in the accent color for a link. |

## Rules

1. Draw text from items as text. JSX does that. `scripts/no-html.test.ts` fails on `dangerouslySetInnerHTML` or `innerHTML` in `packages/ui/src`.
2. Use `ActionButton` for each manifest action, so the label and the style match the host dialog.
3. Open a link only through `openLink` or a control that calls it.
