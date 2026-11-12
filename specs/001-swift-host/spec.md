# Feature Specification: Swift host with JavaScript plugins

**Feature Branch**: `001-swift-host`

**Created**: 2026-11-09

**Status**: Implemented

**Input**: User description: "A macOS app in Swift runs routines on one Mac. Each routine is a plugin: a manifest and one JavaScript bundle that runs in JavaScriptCore. The manifest declares the schedule, the settings, the permissions and the actions of the plugin. The host refuses each call that the manifest does not allow. The Inbox lists the work of all plugins that needs you. A coding agent in the app makes new plugins."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Plugins run on their schedule (Priority: P1)

You add a plugin folder to a plugin folder of the app. The sidebar lists the plugin. Its manifest declares clock slots, and the app runs the plugin at each slot. The app never runs two copies of one plugin at the same time. After the Mac wakes, the app runs each plugin with a missed slot once.

**Why this priority**: scheduled runs are the main task of the app.

**Independent Test**: load the `echo` fixture plugin and move the host clock past its slot. Make sure that one run starts with the trigger `schedule`.

**Acceptance Scenarios**:

1. **Given** a plugin runs, **When** its next slot comes, **Then** the app skips that slot and records the skip in Runs.
2. **Given** an action of the plugin calls `runSoon`, **When** the requested time comes, **Then** the app starts one run with the trigger `soon`.
3. **Given** the Mac slept through two slots, **When** it wakes, **Then** the app runs the plugin once.
4. **Given** a manifest with `runAtLaunch: true`, **When** the app starts, **Then** the plugin runs with the trigger `launch`.

---

### User Story 2 - A plugin gets only what its manifest declares (Priority: P1)

A plugin reaches the Mac only through the host. The host checks each command, HTTP host, file path and browser call against the `permissions` of the manifest. It refuses each other call and returns the reason as an error value.

**Why this priority**: you can read one file and know what a plugin can reach.

**Independent Test**: run the `echo` fixture plugin, which tries `rm` and a read of `/etc/hosts`, and make sure that both calls fail with `denied`.

**Acceptance Scenarios**:

1. **Given** `permissions.exec` lists only `echo`, **When** the plugin runs `rm`, **Then** the call returns `denied` and the run log has the refusal.
2. **Given** a path outside the allowed folders, **When** the plugin reads it, **Then** the call returns `denied`.
3. **Given** a symbolic link in an allowed folder points outside, **When** the plugin reads the link, **Then** the call returns `denied`.
4. **Given** `permissions.exec` lists `env`, **When** the plugin runs `env rm`, **Then** the call returns `denied`.

---

### User Story 3 - See the work that needs you (Priority: P1)

Each plugin keeps its items as cards. A card has a column: Planned, In progress, Needs you, Done or Failed. The Inbox lists the cards of all plugins in Needs you, newest first. The sidebar and the menu bar count them. A click on an Inbox row or on a notification opens the plugin, and its UI shows the item.

**Why this priority**: the Inbox is the one place where you see the work that waits for you.

**Independent Test**: run a plugin that adds a card in `needs-you`, and make sure that the Inbox lists it with the plugin.

**Acceptance Scenarios**:

1. **Given** a card is in Needs you, **When** you open the Inbox, **Then** the Inbox shows the card and its plugin.
2. **Given** you type text in the Inbox search, **When** the text matches a card, **Then** only the matching cards stay. The search reads the title, the body, the status and the tags.
3. **Given** a notification with a `cardId`, **When** you click it, **Then** the app opens the plugin, and its UI shows that item.

---

### User Story 4 - Act on an item or on a plugin (Priority: P1)

The manifest lists each action of a plugin. You press an action in the plugin UI. The host finds the action in the manifest and calls the plugin. The card or the plugin shows the answer. The rules of the press are in `specs/003-custom-ui-everywhere/`.

**Why this priority**: approvals and answers are how you control a routine.

**Independent Test**: load the `echo` fixture plugin and perform its `done` action on a card. Make sure that the card moves to Done with the answer as its status.

**Acceptance Scenarios**:

1. **Given** an action runs, **When** the plugin has not answered, **Then** the card shows "Working on it…".
2. **Given** the handler throws an error, **When** the action ends, **Then** the card shows the error and the action counts as failed.
3. **Given** an action that the manifest does not list, **When** a page asks for it, **Then** the host refuses it.
4. **Given** a long run of the plugin, **When** you press an action, **Then** the action runs at once and does not wait for the run.

---

### User Story 5 - Settings, notes and an off switch per plugin (Priority: P2)

Each plugin has a Settings tab. It holds the fields of the manifest, your notes, the permissions and a switch to turn the plugin off. Only you can add a note, so text from other people cannot teach a routine.

**Why this priority**: you configure and teach each routine without a change to its code.

**Independent Test**: add a note in the Settings tab, run a plugin that reads its notes, and make sure that the plugin gets the note.

**Acceptance Scenarios**:

1. **Given** you add a note, **When** the plugin calls `notes.list`, **Then** the list has the note.
2. **Given** a required setting is empty, **When** a slot is due, **Then** the app does not run the plugin. The plugin page names the setting.
3. **Given** a setting is empty and has a `default`, **When** the plugin runs, **Then** it gets the default.
4. **Given** you choose a retention for done cards, **When** that time passes, **Then** the host deletes the done and failed cards.

---

### User Story 6 - See what a run did (Priority: P2)

The Runs view lists each run and each action, newest first, with the plugin, the trigger, the start, the time and the result. A click on a row opens its log.

**Why this priority**: you find out why a routine failed without a terminal.

**Independent Test**: run the `echo` fixture plugin and make sure that Runs has the run and that its log has the `console.log` line.

---

### User Story 7 - Make a plugin in a thread (Priority: P2)

You open Threads, press New thread and describe a routine. The coding agent, Claude Code or Codex, builds the plugin in the workspace of the app. The plugin shows in the sidebar after the build. You turn it on and fill its settings.

**Why this priority**: you get a new routine without a separate repo or a manual build.

**Independent Test**: start a thread and ask for a plugin that adds one item each hour. Make sure that the plugin loads after the build.

**Acceptance Scenarios**:

1. **Given** a plugin in the workspace has a problem, **When** you send the next message, **Then** the `<routines-app>` block of the turn names the problem.
2. **Given** the app updates its workspace source, **When** the app starts, **Then** it replaces the app-owned files and keeps `plugins/`.

---

### User Story 8 - Start an action from another program (Priority: P3)

A script runs `Routines --perform <plugin> <action> [text]`. The app runs the plugin action and the command prints the answer. Only an action in `permissions.external` runs this way.

**Why this priority**: a shortcut or a script can drive a routine without the app window.

**Independent Test**: check an external request against a manifest, and make sure that only a listed plugin action passes.

---

### Edge Cases

- A plugin throws an error or never settles its promise. The host marks the call as failed after `timeoutMinutes`, frees its locks and closes its browser pages.
- A manifest does not parse, its id does not match the folder or its bundle is missing. The sidebar shows a warning, the Settings tab shows the problem, and the plugin does not run.
- A bundle throws at load or does not call `definePlugin`. Each call of the plugin fails with that error.
- Two plugins update the same state file. `updateStateFile` takes a host lock, so the updates happen one after the other.
- A card id repeats. The second write replaces the first card and keeps its place.
- A cards file does not parse. The host keeps the file and refuses each write to it.
- The app quits during a run. At the next start, Runs shows the run as failed, and the next slot runs the plugin again.
- Two plugin folders hold the same id. The plugin of the later folder wins.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The host MUST find plugins in `ROUTINES_PLUGINS_DIR`, in `<data folder>/plugins` and in `<data folder>/workspace/plugins`, in this order.
- **FR-002**: The host MUST run each call of a plugin in a new JavaScriptCore context on its own queue.
- **FR-003**: The host MUST give each context `fetch`, timers, `URL`, `console`, text encoding, base64 and random values.
- **FR-004**: The host MUST give plugins these calls: commands, HTTP, files, locks, cards, notifications, requested runs, notes, activity, a page and off-screen WebKit pages.
- **FR-005**: The host MUST refuse each command, host, path, browser call and activity read that the manifest does not allow.
- **FR-006**: The host MUST run plugins on the clock slots of their manifest, with one run per plugin at a time.
- **FR-007**: The host MUST run the actions of a plugin one after another, apart from its runs.
- **FR-008**: The host MUST record each run and each action with its start, end, outcome, message and log file.
- **FR-009**: The app MUST show a sidebar with Inbox, Threads, Runs, a search field and one row per plugin that is not hidden.
- **FR-010**: The app MUST show a page per plugin with the tabs Runs and Settings. For a manifest with `ui`, the UI tab MUST come first.
- **FR-011**: The app MUST let you edit the settings and the notes of each plugin. You MUST be able to turn it off, pin it and choose its retention of done cards.
- **FR-012**: The host MUST call an action only after it finds the action in the manifest and checks its target, its item and its text.
- **FR-013**: The app MUST show a macOS notification for each `notify` call, and a click MUST open the plugin.
- **FR-014**: The binary MUST act as the `PreToolUse` hook of guarded agent tools with `--tool-guard`.
- **FR-015**: The binary MUST ask the running app for an external plugin action with `--perform` and print the answer.
- **FR-016**: The app MUST run thread turns with Claude Code or Codex in its workspace, and it MUST keep each thread on its first agent.
- **FR-017**: After a change of the workspace version, the app MUST install the workspace source. It MUST never change `workspace/plugins`.
- **FR-018**: The app MUST be able to open at login.

### Key Entities

- **Plugin**: a folder with `plugin.json` and a JavaScript bundle. Its manifest holds the id, the name, the schedule, the settings, the permissions, the actions and the UI title.
- **Card**: one item of work of a plugin, with an id, a title, a column and optional body, progress, date, tags, links, images, status and data.
- **Run record**: one run or one action, with its trigger, start, end, outcome, message and log file.
- **Note**: a text that you add to a plugin. The plugin reads it.
- **Page**: a list of Markdown and status blocks that a plugin publishes for its UI.
- **Thread**: a conversation with the coding agent, with its agent, its session and its items.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `bun run check` passes: the token check, the type check, the package tests and the host tests.
- **SC-002**: No plugin runs a command, reads a path or reaches a host outside its manifest. `PermissionTests` and `HostTests` prove this.
- **SC-003**: No caller runs an action that the manifest does not list, or an item action without its item. `ActionLookupTests` and `ExternalActionTests` prove this.
- **SC-004**: A Mac that slept through many slots runs a plugin once. `ScheduleTests` proves this.
- **SC-005**: Each built plugin in a folder loads in JavaScriptCore. `PluginBundleTests` with `ROUTINES_PLUGINS_DIR` proves this.

## Assumptions

- The app runs on one Mac for one person. It has no accounts and no sync.
- The app ships with no plugins. You make them in a thread or install them from a repo of your own.
- Plugins share the state folder `~/.local/state/routines`. A plugin keeps its secrets in files that you write, and it lists them in `permissions.paths`.
- Agent nodes and threads use the Claude Code login in `~/.claude`. Codex uses its own login.
- Claude Code, Codex and Bun are on the PATH of the host. The host adds `~/.local/bin`, `~/.bun/bin`, `/opt/homebrew/bin` and `/usr/local/bin` to it.
