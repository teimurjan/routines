# Design guide

This guide describes the look of the Routines app and of each plugin UI. A plugin UI is a page that a plugin ships in `dist/ui`, and the app shows it in a tab. The app and the plugin UIs take their style from one file, `design/tokens.json`.

## How the tokens reach the app and the pages

A token is one named style value, for example a color or a font size. `scripts/build-tokens.ts` reads `design/tokens.json` and writes two files:

- `app/Sources/Routines/Views/Tokens.swift`, which the Swift views use through `Tokens` and `Theme`.
- `packages/ui/src/tokens.css`, which each plugin UI gets from `@routines/ui`.

Do not edit the two generated files. If a Swift view outside `Tokens.swift` and `Theme.swift` sets a color, a font size or a radius as a number, `TokenUseTests` fails.

### Change a token

1. Edit the value in `design/tokens.json`.
2. Run `bun run tokens`.
3. Build each plugin again, so its UI gets the new CSS.
4. Run `bun run check`. If a generated file does not match `design/tokens.json`, the command fails.

The format of the file is in [specs/002-plugin-ui/contracts/tokens.md](specs/002-plugin-ui/contracts/tokens.md).

## Colors

Each color has a light value and a dark value. The app picks the value of the current appearance. A page gets the same values through `prefers-color-scheme`.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `canvas` | `#FFFFFF` | `#141415` | Page background and the background of each plugin UI. |
| `sidebar` | `#F7F7F8` | `#1C1C1E` | Sidebar. |
| `column` | `#F4F4F5` | `#1F1F22` | Board column, log view and other sunken areas. |
| `column-border` | `#E8E8EA` | `#2C2C30` | Border of a board column. |
| `card` | `#FFFFFF` | `#26262A` | Card, pill, selected tab and normal button fill. |
| `card-border` | `#E6E6E9` | `#34343A` | Border of a card, pill, field and normal button. |
| `pill` | `#EFEFF1` | `#2C2C30` | Tab strip track and sidebar count. |
| `selection` | `#ECECEE` | `#2C2C30` | Selected sidebar row. |
| `text` | `#000000D9` | `#FFFFFFD9` | Main text. These are the values of the system label color. |
| `muted` | `#6B6B73` | `#9A9AA2` | Secondary text. |
| `faint` | `#9B9BA3` | `#6E6E76` | Icons, hints and empty states. |
| `danger` | `#E5484D` | `#FF6369` | Destructive button text and errors. |
| `success` | `#1F9D55` | `#3DD68C` | Done and good progress. |
| `warning` | `#F59E0B` | `#FBBF24` | In progress, medium progress and banners. |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on a primary button. |

The accent color is the accent color of the Mac, so it is not a token. The app uses `Color.accentColor`. A page gets it as `--accent`. When you change it in System Settings, the host sends the new value.

A tint is a color at the opacity of a token:

| Token | Value | Use |
| --- | --- | --- |
| `opacity-tint` | 0.1 | Fill of a destructive button and of a banner. |
| `opacity-pressed` | 0.75 | A button while you press it. |

## Type

The font is the system font. Swift uses `.system(size:weight:)` through `Tokens.Font`. CSS uses `-apple-system, system-ui` with `--font-<name>-size` and `--font-<name>-weight`.

| Token | Size | Weight | Use |
| --- | --- | --- | --- |
| `display` | 26 | bold | Page title. |
| `title` | 20 | bold | Title of a sheet or a dialog. |
| `heading-1` | 19 | semibold | Markdown heading 1. |
| `headline` | 18 | semibold | Section title. |
| `heading-2` | 15.5 | semibold | Markdown heading 2. |
| `subhead` | 15 | semibold | Label of a status block. |
| `card-title` | 14 | semibold | Card title and Markdown heading 3. |
| `column-title` | 14 | medium | Title and icon of a board column. |
| `body-large` | 13.5 | regular | Page text and sidebar rows. |
| `body` | 13 | regular | Card body, fields, tabs and the breadcrumb. |
| `row-title` | 13 | medium | Title of a list row. |
| `small` | 12.5 | regular | Banner text and dense rows. |
| `meta` | 12 | regular | Dates, status lines and list rows. |
| `button` | 12 | medium | Button label and column count. |
| `caption` | 11.5 | medium | Pills, sidebar section labels and the plugin name on a card. |
| `mono` | 11.5 | regular | Run logs, in the monospaced design. |
| `label` | 11 | semibold | Sidebar counts. |
| `micro` | 10 | semibold | Breadcrumb chevron. |

A selected tab shows `body` at semibold. A selected sidebar row shows `body-large` at medium.

## Spacing

All values are points in Swift and pixels in CSS.

| Token | Value | Use |
| --- | --- | --- |
| `space-1` to `space-28` | 1, 2, 3, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 28 | Gaps and padding. `space-14` is the padding of a card. |
| `size-page-gutter` | 28 | Left and right padding of a page. |
| `size-page-top` | 18 | Top padding of a page header and of the tab row. |
| `size-tab-min-width` | 76 | The smallest width of a tab. |
| `padding-pill` | 7 by 3.5 | Pill. |
| `padding-button` | 9 by 4.5 | Button. |
| `padding-field` | 10 by 7 | Search field. |
| `padding-tab` | 0 by 6 | Tab. |

## Radii and shadows

| Token | Value | Use |
| --- | --- | --- |
| `radius-card` | 14 | Card and status block. |
| `radius-sheet` | 18 | Board column. |
| `radius-panel` | 12 | Log view. |
| `radius-track` | 10 | Tab strip track, banner and image. |
| `radius-field` | 9 | Search field and sidebar row. |
| `radius-control` | 7 | Button, pill and selected tab. |
| `shadow-card` | black at 0.04, blur 2, y 1 | Card. |
| `shadow-segment` | black at 0.08, blur 1.5, y 1 | Selected tab. |

SwiftUI and CSS draw a shadow blur in different ways. If the two look different, change the shadow token, not one output.

## Controls

`@routines/ui` gives a Preact version of each control of the app, and the controls that each plugin UI shares. The Swift view and the Preact control use the same tokens. Import the package once, and its CSS comes with it.

```tsx
import { ActionButton, Board, BoardCard, Button, Card, DetailPane, ItemBoard, Markdown, mount, PageHeader, Pill, ProgressRing, SearchField, Status, TabStrip, useSnapshot, Workspace } from "@routines/ui";
```

### PageHeader

The breadcrumb, the title in `display` and an optional subtitle in `body` and `muted`. Controls go on the right.

```tsx
<PageHeader trail={["Routines", "Tickets"]} title="🎫 Tickets" subtitle="Lists the open tickets.">
  <Button onClick={refresh}>Refresh</Button>
</PageHeader>
```

### TabStrip

A `pill` track with a raised `card` segment and `shadow-segment` for the selected tab. The selected label is `text` at semibold. The other labels are `muted`.

```tsx
<TabStrip tabs={[{ id: "queue", label: "Queue" }, { id: "trashed", label: "Trashed" }]} selected={tab} onSelect={setTab} />
```

### SearchField

A field on `canvas` with a `card-border` border, `radius-field` and a `faint` icon. When the field has text, a clear button shows.

```tsx
<SearchField value={query} onInput={setQuery} placeholder="Search matches" />
```

### Card

A `card` fill, a `card-border` border, `radius-card` and `shadow-card`. The title is `card-title`, and the body is `body` in `muted`, at most 3 lines. A status that starts with "Error" shows in `danger`. With `selected`, the border takes the accent color.

```tsx
<Card title={item.title} body={item.body} status={item.status} footer={<Button onClick={done}>Done</Button>} />
```

### Pill

A small label in `caption`, with `padding-pill`, `radius-control` and a `card-border` border.

```tsx
<Pill>Copart</Pill>
```

### Button

Three variants, as the `style` of a card action:

| Variant | Fill | Text |
| --- | --- | --- |
| `primary` | accent | `on-accent` |
| `destructive` | `danger` at `opacity-tint` | `danger` |
| `normal` | `card`, with a `card-border` border | `text` |

A pressed button shows at `opacity-pressed`. A disabled button shows at half opacity. With `shortcut`, the button shows its key.

```tsx
<Button variant="destructive" shortcut="T" disabled={isPending(item.id)} onClick={trash}>Trash</Button>
```

### Status

A dot, a label in `subhead` and an optional detail in `muted`. The dot is `success` for `ok`, `warning` for `warning`, `danger` for `error` and `faint` for `neutral`.

```tsx
<Status state="ok" label="Up to date" detail="Last scan at 10:30." />
```

### ProgressRing

A 12 point ring with a `card-border` track. The value is `faint` below 1%, `warning` below 60% and `success` from 60%.

```tsx
<Pill><ProgressRing value={0.4} /> 40%</Pill>
```

### Markdown

Draws the Markdown of an item body or a page block as elements: headings, list items, paragraphs, bold, italic, inline code and fenced code. A link is a text button in the accent color that opens in the default browser. A link that is not `http` or `https` shows as text. Inside a card, the text is `muted`.

```tsx
<Markdown text={item.body ?? ""} />
```

### ActionButton

A manifest action as a `Button`, with the label and the style of the manifest. With `cardId`, it runs an item action, and without it, a plugin action. An action with `input` shows a field and the button, and the button stays disabled while the field is blank. While the action runs, the button is disabled. An error other than Cancelled shows under it in `danger`. An id that the manifest does not list draws nothing.

```tsx
<ActionButton actionId="approve" cardId={item.id} />
<ActionButton actionId="new-job" />
```

### Board and BoardCard

A plugin UI uses the full width of its tab. `Board` puts its columns side by side, and each column fills an equal part of the width. A column is a `column` area with `radius-sheet`. Its head has a dot, the title in `column-title` and a count. The dot is the accent color for `accent`, and the color of the token for `warning`, `danger` and `success`. A narrow window scrolls the board sideways.

`BoardCard` is a compact card: a title of at most 2 lines, a preview of at most 2 lines and a meta row. An item that needs you has a dot in the accent color. With `dense`, the card is one line, for long lists. With `selected`, the border takes the accent color. A press or the Return key calls `onOpen`, and a press on a button in the footer does not.

```tsx
<Board columns={[{ id: "created", title: "Created", tone: "neutral", items }]} keyOf={({ id }) => id} renderItem={(item) => <BoardCard dense title={item.title} />} />
```

### Workspace and DetailPane

`Workspace` shows the main view, and the detail of the selected item at its right side. `DetailPane` is a `card` panel that stays in view while the page scrolls. Escape and the close button close it.

### ItemBoard

`ItemBoard` draws stored items as a `Board`, by default one column per state that has items. A press on a card opens the full item in a `DetailPane`: the image, the date, the tags, the status, the links, the actions and the body as `Markdown`. A notification of an item opens it too. `actions(item)` gives the buttons of the detail, and `quickActions(item)` gives the buttons on the card. `columns` and `sort` change the columns and the order in each column.

```tsx
<ItemBoard items={snapshot.items} empty="No PR is open." actions={(item) => <DoneButton item={item} />} />
```

### PageBlocks

The blocks of `page.publish`: `Markdown` for a Markdown block and `Status` for a status block, under the time of the last change. Next status blocks show as one grid. Next Markdown blocks flow in columns of about 420 pixels, so a wide window keeps short lines.

```tsx
<PageBlocks page={snapshot.page} empty="The next run writes this page." />
```

### Page layout

`mount(App)` renders a page after its first snapshot. These classes give each page the layout of the app:

| Class | Use |
| --- | --- |
| `rt-page` | The page, a column with `size-page-gutter` on each side and at the bottom. |
| `rt-toolbar` | A row of plugin actions above the content. `rt-toolbar__spacer` pushes the next controls to the right. |
| `rt-note` | One line of `meta` text in `muted`, for example the answer of the last action. |
| `rt-empty` | The text of an empty list, in `faint`. |

## Rules for plugin UIs

The full contract is in [specs/002-plugin-ui/contracts/plugin-ui.md](specs/002-plugin-ui/contracts/plugin-ui.md).

1. Show text from items as text. JSX does that. If a file in `packages/ui/src` contains `dangerouslySetInnerHTML` or `innerHTML`, a test fails. A plugin repo can keep the same test for its UIs.
2. Use the controls and the tokens of `@routines/ui`. Do not set a color, a font size or a radius as a literal.
3. Keep no state that the host does not have. A reload shows the same page.
4. Leave the dialog to the host. If an action has `confirm: true`, the host shows its own dialog, so do not add a second one.
5. Give each keyboard key a visible button with the same action and label.
6. Take each action from the manifest. `ActionButton` reads its label and style there, so the button and the host dialog use the same words.

The page has no network and loads only the files of its own `dist/ui`. A link opens in the default browser only through `openLink`.
