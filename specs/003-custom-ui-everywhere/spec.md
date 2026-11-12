# Feature Specification: Plugin UIs and manifest actions

**Feature Branch**: `003-custom-ui-everywhere`

**Created**: 2026-11-09

**Status**: Implemented

**Input**: Each plugin shows its items in its own UI. The manifest lists each action of a plugin, with its target. Each press goes through one host gate, and an action with `confirm: true` shows a native dialog first. The Inbox lists the items of all plugins that need you, and a row opens the item in its plugin UI. `@routines/ui` gives the shared controls of a plugin UI.

## User Scenarios & Testing

### User Story 1 - The host checks each press against the manifest (Priority: P1)

A plugin lists all its actions once, in `plugin.json`. Each action names its target: one item or the plugin. An item carries no actions. You press each action in the UI of the plugin. The host finds the action in the manifest and checks it before it calls the plugin.

**Why this priority**: the host trusts no page. The manifest is the one list that the host checks each press against.

**Independent Test**: load the fixture `ui-plugin`. Its manifest lists item actions, plugin actions, actions with `confirm: true` and actions with `input`. Send each bridge message with a good action and with a bad one. `PluginUIBridgeTests` and `ActionLookupTests` do this.

**Acceptance Scenarios**:

1. **Given** a listed item action, **When** the UI sends it with an item of the plugin, **Then** the host calls `onAction`.
2. **Given** a listed plugin action, **When** the UI sends it without an item, **Then** the host calls `onPluginAction` with the action id and the text.
3. **Given** the manifest does not list an action id, **When** the UI sends it, **Then** the host refuses it and calls no handler.
4. **Given** an item action, **When** the UI sends it without an item or with an unknown item, **Then** the host refuses it.
5. **Given** a plugin action, **When** the UI sends it with an item, **Then** the host refuses it.
6. **Given** an action with `input`, **When** the UI sends it with no text or with blank text, **Then** the host refuses it.

---

### User Story 2 - The host asks first for a marked action (Priority: P1)

An action with `confirm: true` shows a native dialog before the plugin gets it. The dialog names the action and the item, or the plugin for a plugin action. The page cannot turn the dialog off or rename the action.

**Why this priority**: a destructive action must not run from one press of a page that the host does not control.

**Independent Test**: in the fixture `ui-plugin`, send `trash` for an item and `wipe` for the plugin. The decision is `confirm`, with the stored item title or the plugin name. Add `"confirm": false` and a new label to the message. The decision stays the same.

**Acceptance Scenarios**:

1. **Given** an item action with `confirm: true`, **When** the UI sends it, **Then** the dialog shows the label and the stored title of the item.
2. **Given** a plugin action with `confirm: true`, **When** the UI sends it, **Then** the dialog shows the label and the name of the plugin.
3. **Given** the dialog shows, **When** you press Cancel or Escape, **Then** no handler runs, and the page gets the error `Cancelled.`.
4. **Given** the dialog shows, **When** you press the action button or Return, **Then** the host queues the action.
5. **Given** a message with its own `confirm` or `label` field, **When** the host decides it, **Then** the host ignores those fields.

---

### User Story 3 - Each plugin shows its own UI (Priority: P1)

You open a plugin. If its manifest has `ui`, the first tab is its UI with the label `ui.title`. Runs and Settings follow. The UI gets a snapshot of the items, the page blocks, the actions and the pending actions of its own plugin. When a run changes the items, the UI shows the change without a reload.

**Why this priority**: each routine needs a view that fits its work. The app has no generic view of items.

**Independent Test**: run the app with `ROUTINES_PLUGINS_DIR` set to `app/Tests/RoutinesKitTests/Fixtures`. Open "UI Plugin". The tabs are Items, Runs and Settings.

**Acceptance Scenarios**:

1. **Given** a plugin with `ui`, **When** you open it, **Then** the tabs are its UI, Runs and Settings, and the UI tab is selected.
2. **Given** a plugin without `ui`, **When** you open it, **Then** a banner says so, and the tabs are Runs and Settings.
3. **Given** a UI is open, **When** the items or the page change, **Then** the host sends a new snapshot.
4. **Given** the page does not load, **When** the load fails, **Then** the tab shows "The UI did not load", the reason and a Reload button.

---

### User Story 4 - The Inbox opens the item in its plugin UI (Priority: P1)

The Inbox lists the items of all plugins that need you, newest first. A row shows the plugin mark, the title, one line of the body, the status and the date. You click a row, and the app opens the plugin. Its UI then shows the item. A notification of an item does the same.

**Why this priority**: the Inbox is the one place to find work that needs you. A row must lead to the place where you act on it.

**Independent Test**: give two plugins one item each in `needs-you`. Click each row. The app opens the right plugin, and its page gets a `focus` event with the item id.

**Acceptance Scenarios**:

1. **Given** an item needs you, **When** you click its row, **Then** the app opens its plugin and sends `focus` to the UI.
2. **Given** the UI did not send `ready` yet, **When** you click a row, **Then** the host sends `focus` after `ready`.
3. **Given** the plugin has no UI, **When** you click a row, **Then** the app opens the plugin page only.
4. **Given** you type in the Inbox search field, **When** the text matches an item, **Then** its row stays, and the other rows hide.

---

### User Story 5 - Another program starts a plugin action (Priority: P2)

`Routines --perform <plugin> <action> [text]` asks the running app for an action and prints its answer. The app runs only a plugin action that `permissions.external` lists. It shows no dialog, because nobody is at the Mac to answer it.

**Why this priority**: a script or an agent outside the app can start a routine without the UI.

**Independent Test**: `ExternalActionTests` checks a listed action, an unlisted action, an item action and a reply file outside the replies folder.

**Acceptance Scenarios**:

1. **Given** a plugin action in `permissions.external`, **When** another program asks for it, **Then** the command prints the answer of the plugin.
2. **Given** an action that `permissions.external` does not list, **When** another program asks for it, **Then** the host refuses it.
3. **Given** an item action in `permissions.external`, **When** another program asks for it, **Then** the host refuses it, because the call names no item.
4. **Given** a reply file outside the replies folder of the app, **When** another program asks for an action, **Then** the host refuses it.

---

### User Story 6 - Shared controls make a UI look like a part of the app (Priority: P2)

A plugin author builds a UI from `@routines/ui`. `ActionButton` draws a manifest action with its label and its style. `Markdown` draws the Markdown of an item body or a page block as elements. `ItemBoard` draws the items by state, with a detail pane. `PageBlocks` draws the page blocks.

**Why this priority**: each plugin UI must follow `DESIGN.md` without its own copy of each control.

**Independent Test**: run `bun test packages scripts`. The tests cover the Markdown parser, the groups by state, the bridge client, the action lookup and the ban on HTML sinks.

**Acceptance Scenarios**:

1. **Given** a body with headings, lists, links and code, **When** `Markdown` draws it, **Then** no text becomes HTML.
2. **Given** a link that is not `http` or `https`, **When** the parser reads it, **Then** the link becomes text.
3. **Given** an `ActionButton` with an unlisted id or a wrong target, **When** it renders, **Then** it draws nothing.
4. **Given** an action with `input`, **When** `ActionButton` renders it, **Then** it shows a field and a button. A blank field disables the button.
5. **Given** items in several states, **When** `byState` groups them, **Then** the items that need you come first. An empty group is left out.

---

### Edge Cases

- A stored item with an `actions` key loads. The host ignores the key, and the next save drops it.
- A manifest with a key that the host does not know decodes. The host ignores the key.
- An item action names an item that the plugin removed after the press. The host refuses it.
- The page names an item of another plugin. The host looks only in the store of its own plugin, so it refuses the item.
- You press a button while an action of the same item runs. The button is disabled, and the host runs the actions of a plugin one after another in one queue.
- A plugin has a problem, for example a missing bundle. Each action fails with the problem, and the status shows `Error: <problem>`.
- The page sends a message with an unknown type. The host refuses it.
- The page runs outside the app. Each bridge call fails with "the page runs outside the Routines app".
- The page asks to open a link that is not `http` or `https`. The host refuses it.

## Requirements

### Functional Requirements

- **FR-001**: The manifest MUST list each action of its plugin in `actions`. An action has an `id` and a `label`, and optionally a `style`, an `input`, `confirm` and a `target`.
- **FR-002**: `target` MUST be `item` or `plugin`. An action without `target` MUST be a plugin action.
- **FR-003**: An item MUST NOT carry actions. The host MUST ignore an `actions` key of a stored item.
- **FR-004**: The host MUST refuse an action id that the manifest does not list.
- **FR-005**: The host MUST refuse an item action without an item, or with an item that its plugin does not have. It MUST refuse a plugin action with an item.
- **FR-006**: If an action has `input` and the text is missing or blank, the host MUST refuse it.
- **FR-007**: For an action with `confirm: true`, the app MUST show its own dialog before it calls the plugin. The dialog MUST name the action, and the stored item title or the plugin name. Cancel MUST call no handler.
- **FR-008**: In the app target, only `ActionGate` MUST call `perform` and `performPluginAction` of the host.
- **FR-009**: The app MUST draw no action control of its own: no action button, no action menu, no text field for actions and no item detail.
- **FR-010**: If the manifest has `ui`, the plugin page MUST show its UI tab first, then Runs and Settings.
- **FR-011**: A plugin without `ui` MUST load and run. Its page MUST show a banner, then Runs and Settings.
- **FR-012**: The snapshot of a UI MUST hold only the items, the page, the actions and the pending actions of its own plugin.
- **FR-013**: The page blocks of a plugin MUST reach only the UI of the same plugin. The app MUST NOT draw them.
- **FR-014**: The Inbox MUST list the items in `needs-you` of all plugins, hidden plugins too, newest first. A row and a notification MUST open the plugin and send `focus` to its UI after `ready`.
- **FR-015**: Another program MUST be able to start only a plugin action that `permissions.external` lists. An external action MUST show no dialog.
- **FR-016**: The Markdown parser of `@routines/ui` MUST return nodes, never HTML. Only an `http` or `https` link MUST be active.
- **FR-017**: `ActionButton` MUST take the label, the style and the input of an action from the snapshot. It MUST draw nothing for an unlisted id or a wrong target.

### Key Entities

- **Plugin action**: one entry of `actions` in the manifest. It has an id, a label, a style, an optional text prompt, a flag for the dialog and its target.
- **Item**: one card of a plugin. It has a title, a body, a state, links, images, a status and data for the UI. It carries no actions.
- **Plugin page**: the blocks that a plugin publishes with `page.publish`. Only its own UI shows them.
- **Snapshot**: what a UI gets from the host. It holds the plugin, its items, its page, its actions, its pending actions, the status and the appearance.
- **Inbox row**: an item in `needs-you`, with its plugin.

## Success Criteria

### Measurable Outcomes

- **SC-001**: In the host tests, each call with an unlisted id, a wrong target, an unknown item or blank text fails. It leaves no run record and no pending action.
- **SC-002**: In the bridge tests, each action with `confirm: true` becomes a `confirm` decision with the stored title. A field of the message does not change it.
- **SC-003**: `NativeActionsGoneTests` passes. Only `ActionGate.swift` calls the actions of the host, and no app view names an action control.
- **SC-004**: In `PluginUIWebKitTests`, the call of an unlisted action from the hostile page fails.
- **SC-005**: `bun test packages scripts` passes, with tests of the Markdown parser, `byState`, the bridge client and `actionOf`.

## Assumptions

- The security rules of a plugin UI are in `specs/002-plugin-ui`: the scheme, the content policy, the content rules, the navigation guard and the data store. This feature uses them as they are.
- The bridge has no message that deletes an item. The retention in the Settings tab deletes done and failed items after `doneCards.retentionDays`.
- The app has no "Run now" button. A plugin that needs a run on request lists a plugin action that calls `runSoon`.
- The app ships no plugins. The fixtures in `app/Tests/RoutinesKitTests/Fixtures` are the only plugins in this repo.
