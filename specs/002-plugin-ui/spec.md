# Feature Specification: Plugin UI in HTML and JavaScript

**Feature Branch**: `002-plugin-ui`

**Created**: 2026-11-09

**Status**: Implemented

**Input**: A plugin can ship a UI page that the Swift host shows as a tab of the plugin page. The host serves the page with a strict content policy and a bridge to the items and actions of its own plugin. The host asks you itself before a marked action. The page matches the app in light and dark mode. One token file gives the style to the app and to each page, and a design guide describes it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A plugin shows its own UI (Priority: P1)

You open a plugin that ships a UI. Its page shows that UI as the first tab, then Runs and Settings. The UI draws the items of the plugin in the shape that fits its work, for example a list of open tickets. It looks like a part of the app: the same background, fonts, colors and controls. When the Mac changes between light and dark mode, the UI follows at once.

**Why this priority**: every other story needs a page that the host shows.

**Independent Test**: load the fixture `app/Tests/RoutinesKitTests/Fixtures/ui-plugin` and give it two items. Open its page. The list shows the two titles, and the background matches the app in both modes.

**Acceptance Scenarios**:

1. **Given** a plugin ships a UI, **When** you open its page, **Then** the first tab shows the UI with no white frame.
2. **Given** the UI is open, **When** a run or an action changes an item, **Then** the UI shows the change without a reload.
3. **Given** the UI is open, **When** you switch to dark mode, **Then** the UI and the app change together.
4. **Given** the UI is open, **When** you change the accent color of the Mac, **Then** the UI uses the new accent color.
5. **Given** a plugin ships no UI, **When** you open its page, **Then** the page shows Runs and Settings under a banner.

---

### User Story 2 - Act from the plugin UI (Priority: P1)

You press a button in a plugin UI, for example Close on a ticket. The host finds the action in the manifest and calls the handler of the plugin. For an action with `confirm: true`, the host first shows its own dialog. The dialog names the action and the item, with text from the manifest and the host store.

**Why this priority**: a UI without actions only reads. The host dialog keeps a marked action safe from hostile text in a page.

**Independent Test**: load the fixture `ui-plugin`. It has one plain item action and one item action with `confirm: true`. Send each from the bridge. Only the second one becomes a decision that asks you first.

**Acceptance Scenarios**:

1. **Given** an action has `confirm: true`, **When** the UI asks for it, **Then** the host dialog shows before the handler runs.
2. **Given** you press Cancel in the host dialog, **When** the call ends, **Then** no handler runs and the UI gets the error `Cancelled.`.
3. **Given** the manifest does not list an action, **When** the UI asks for it, **Then** the host refuses it and returns the reason.
4. **Given** an action has `input`, **When** the UI sends it with blank text, **Then** the host refuses it.
5. **Given** the handler returns an error, **When** the action ends, **Then** the UI gets the error and can show it.

---

### User Story 3 - One design guide and one token source (Priority: P1)

A plugin author reads one design guide, `DESIGN.md`. It describes the colors, the type sizes, the spacing, the radii, the shadows and the controls of the app, with the name of each token. `@routines/ui` gives the same tokens and controls to each page. When a token changes in `design/tokens.json`, the app and each plugin UI change with it after a build.

**Why this priority**: pages that each pick their own style make the app look like a set of foreign pages.

**Independent Test**: change one color in `design/tokens.json` and run `bun run tokens`. `Tokens.swift` and `tokens.css` both hold the new value.

**Acceptance Scenarios**:

1. **Given** the design guide, **When** you compare it with `design/tokens.json`, **Then** the guide lists each token with its use.
2. **Given** a plugin UI uses the shared controls, **When** you compare it with a native view, **Then** the controls look the same.
3. **Given** a generated file differs from `design/tokens.json`, **When** you run `bun run check`, **Then** the check fails.
4. **Given** a Swift view sets a color, a font size or a radius as a number, **When** the host tests run, **Then** `TokenUseTests` fails.

---

### User Story 4 - Open an item from the Inbox or a notification (Priority: P2)

The Inbox lists the items of all plugins that need you, newest first. You press a row, or a notification of an item. The app opens the plugin, and its UI shows that item.

**Why this priority**: the Inbox is the one view that mixes plugins, so it needs a way into each plugin UI.

**Independent Test**: give a plugin with a UI one item that needs you. Press its Inbox row. The plugin page opens, and the page gets a `focus` event with the item id after `ready`.

**Acceptance Scenarios**:

1. **Given** an item needs you, **When** you open the Inbox, **Then** the list shows its plugin mark, title, first body line, status and date.
2. **Given** you press an Inbox row, **When** the UI sends `ready`, **Then** the host sends `focus` with the id of the item.
3. **Given** the plugin has no UI, **When** you press its Inbox row, **Then** the app opens the plugin page only.

---

### User Story 5 - Build a plugin UI (Priority: P2)

A plugin author writes `ui/main.tsx` next to the plugin source. The build of the workspace bundles it with Preact and writes `dist/ui`. The open UI tab loads the new page after the build.

**Why this priority**: a plugin author needs one fixed way to build a page that the host accepts.

**Independent Test**: make a small plugin with a UI in the workspace and run `bun run build <id>`. `dist/ui` holds `index.html`, `ui.js` and `ui.css`, and the tab shows the page.

**Acceptance Scenarios**:

1. **Given** a plugin has `ui/main.tsx`, **When** you build it, **Then** `dist/ui/index.html` is the fixed shell of the build.
2. **Given** the UI imports no CSS, **When** you build it, **Then** `dist/ui/ui.css` is an empty file.
3. **Given** the UI tab is open, **When** a new `ui.js` lands, **Then** the tab loads the page again.

---

### Edge Cases

- `dist/ui/index.html` is missing. The tab shows "The UI did not load" with the reason and a Reload button.
- The page throws an error or its process stops. The tab shows the error and a Reload button. The runs, the actions and the other plugins keep working.
- The page never sends `ready`. The host shows the web view after 1 second.
- Text from an item holds HTML or script. The page shows it as text, and no script from outside `dist/ui` runs.
- The page tries to load a file, a page or a server outside `dist/ui`. The host refuses the load.
- The page tries to load another page or to open a window. The host cancels the load, and `window.open` returns null.
- The page asks to open a link that is not `http` or `https`. The host refuses it.
- The page asks for an image path that no stored item of the plugin lists. The host refuses it.
- The page names an item of another plugin. The host refuses it, because the bridge knows the plugin id of its web view.
- You press an action twice before the first answer. The button stays disabled while the action is pending, and the host runs the actions of a plugin one after another.
- The appearance of the Mac changes while the tab is hidden. The next open makes a new web view with the current appearance.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A plugin can declare a UI with `ui: { title }` in its manifest. The plugin page then shows the UI as its first tab, with the label `title`.
- **FR-002**: A plugin without `ui` MUST show Runs and Settings under a banner that points to the Inbox.
- **FR-003**: The host MUST serve only the files of `dist/ui` of the plugin and the images that its stored items list. It MUST block every other load, including the network, other plugin folders and remote pages.
- **FR-004**: The host MUST allow script only from files of `dist/ui`. It MUST block inline script and script from any other source.
- **FR-005**: The host MUST give the page only the items, the page blocks, the actions, the pending actions and the status of its own plugin.
- **FR-006**: The host MUST send a new snapshot to the open page after each change of that data or of the appearance.
- **FR-007**: The page MUST be able to call the item actions and the plugin actions of its manifest. The host MUST refuse an unknown action id, a wrong target, an unknown item and a text action without text.
- **FR-008**: For an action with `confirm: true`, the host MUST show its own dialog before it calls the plugin. Cancel MUST call no handler.
- **FR-009**: The dialog MUST take the action label from the manifest and the item title from the host store, not from the page.
- **FR-010**: The page MUST be able to ask the host to open an `http` or `https` link in the default browser. The host MUST refuse every other link.
- **FR-011**: The page background MUST equal the app canvas color in light and dark mode. No white frame MUST show before the first frame of the page.
- **FR-012**: The page MUST follow a change of the Mac appearance and of the accent color without a reload.
- **FR-013**: The project MUST have one token file for colors, opacities, type, spacing, sizes, paddings, radii and shadows. The Swift views and `@routines/ui` MUST both take their values from it.
- **FR-014**: The project MUST have a design guide that describes each token, each shared control and the rules for plugin UIs.
- **FR-015**: `@routines/ui` MUST give the tokens, the shared controls and a typed bridge client.
- **FR-016**: No code in `@routines/ui` MUST insert HTML. Text from items MUST show as text.
- **FR-017**: The build of a plugin UI MUST write `index.html` from one fixed shell, so a plugin cannot add markup to it.
- **FR-018**: The Inbox MUST list the items of all plugins that need you, newest first. A row MUST open the plugin, and its UI MUST get the item id.
- **FR-019**: A crash or a hang of a page MUST not stop the runs, the actions or the views of any plugin.
- **FR-020**: The host MUST name no plugin id.

### Key Entities

- **UI bundle**: the folder `dist/ui` of a plugin, with `index.html`, `ui.js`, `ui.css` and the assets of the build.
- **Item**: one unit of work of a plugin, stored as a card. It has a state, a title, a body, a date, tags, links, images, a status and optional `data` for the UI of its plugin.
- **Action**: an entry of `actions` in the manifest. It targets one item or the plugin. It can ask for text and can ask you first in the host dialog.
- **Snapshot**: the data that the page gets from the host, built from the stores of one plugin.
- **Design token**: one named style value in `design/tokens.json`, for example the canvas color with a light and a dark value.
- **Design guide**: `DESIGN.md`, which describes the tokens, the controls and the rules for plugin UIs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a screenshot of a plugin UI next to a native view, the background colors are equal in light and dark mode.
- **SC-002**: The web view shows at most 1 second after the load starts, and no white frame shows before it.
- **SC-003**: The hostile page in `Fixtures/hostile-ui` fails at each of its seven tries in `PluginUIWebKitTests`.
- **SC-004**: `PluginUIBridgeTests` proves that each action with `confirm: true` becomes a decision that asks you first, and that the message cannot change that.
- **SC-005**: `TokenUseTests` fails on a color, font size or radius literal in the Swift views.
- **SC-006**: `HostIsGenericTests` passes, so the host source names no plugin id.

## Assumptions

- Items stay the data model of the host, because the Inbox, the notifications and `activity.list` read them. A plugin UI is a view over its items and its page, not a second store.
- A plugin UI uses only `@routines/ui`, Preact and its own code. It has no network, so it fetches nothing at run time.
- Each open UI tab has its own web view. When you leave the tab, its web view goes away.
- The app ships with no plugins. The tests use the fixtures in `app/Tests/RoutinesKitTests/Fixtures`.
