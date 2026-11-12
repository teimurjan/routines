# Implementation Plan: Plugin UIs and manifest actions

**Branch**: `003-custom-ui-everywhere` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-custom-ui-everywhere/spec.md`

## Summary

Each plugin shows its items in its own UI, then Runs and Settings. The manifest lists each action once, and each action names its target: one item or the plugin. The host finds each action in the manifest. It checks the target, the item and the text. For `confirm: true`, the app shows a native dialog first. The handler of the plugin checks that the action fits the state of the item.

`ActionGate` is the one entry point for a press in the app. The app draws no action control of its own. The Inbox lists the items that need you, and a row opens the item in its plugin UI. `packages/ui` gives a safe Markdown control, an `ActionButton` that reads the manifest action, board controls for items and a grouping by state.

## Technical Context

**Language/Version**: Swift 6 for the host, TypeScript bundled by Bun 1.3 for plugins and plugin UIs.

**Primary Dependencies**: Apple frameworks in the host. Preact 10.29.8 in `packages/ui` and in each plugin UI. See [research.md](research.md).

**Storage**: The JSON stores in `~/Library/Application Support/Routines`. A stored card has no `actions` field.

**Testing**: `swift test` for the host. `bun test packages scripts` for the SDK, the UI controls and the HTML check. The WebKit test runs only with `ROUTINES_WEBKIT_TESTS=1`.

**Target Platform**: macOS 15 or later.

**Project Type**: A desktop app with a plugin API.

**Performance Goals**: After a click on an Inbox row, the UI gets `focus` as soon as the page sent `ready`.

**Constraints**: No action control in the app outside plugin UIs. No markup from plugin data in a UI. No style literal in a UI or a Swift view.

**Scale/Scope**: The app ships no plugins. The repo has three fixture plugins for the tests: `echo`, `ui-plugin` and `hostile-ui`.

## Constitution Check

| Rule | Status | How the design keeps it |
| --- | --- | --- |
| R1. The host knows no routine | Pass | The host checks generic manifest fields. `HostIsGenericTests` scans each Swift file for a plugin id. |
| R2. Agents decide and code acts | Pass | The feature adds no node. |
| R3. A plugin gets only what its manifest declares | Pass | The manifest is the only source of actions, and the host refuses the rest. `ActionLookupTests` and `PluginUIBridgeTests` cover each refusal. |
| R4. Errors are values | Pass | Each refusal returns `{ ok: false, error }`. |
| R5. State survives a crash | Pass | The UIs keep no state that the host does not have. |
| R6. The host owns the control surface | Pass | Each press goes through `ActionGate`, and the host shows the dialog. `NativeActionsGoneTests` and `PluginUIWebKitTests` check it. |
| R7. Plain code over frameworks | Pass | The Markdown parser is a small module of `packages/ui`, not a library. |

## Project Structure

### Documentation (this feature)

```text
specs/003-custom-ui-everywhere/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    ├── actions.md        # Manifest actions, targets, refusals, the dialog and external actions
    └── ui-controls.md    # Each export of @routines/ui
```

`scripts/build-workspace.ts` copies both contracts into `docs/` of the workspace of the threads.

### Source Code (repository root)

```text
app/Sources/RoutinesKit/
├── Model/Card.swift             # Column, CardAction with target, Card without actions, BoardItem
├── Model/Manifest.swift         # actions, ui, permissions.external, doneCards
├── Model/Page.swift             # PageBlock and Page, data for the UI of the same plugin
├── Host/ActionLookup.swift      # Finds an action in the manifest, checks the target, the item and the text
├── Host/PluginHost.swift        # perform, performPluginAction, performExternal, one action queue per plugin
├── Host/ExternalAction.swift    # routines://perform, plugin actions of permissions.external only
├── UI/PluginUIBridge.swift      # Turns a page message into a reply, a refusal, perform or confirm
└── UI/PluginUISnapshot.swift    # The snapshot of one plugin
app/Sources/Routines/
├── AppModel.swift               # PluginTab, the Inbox items, open(pluginId:cardId:) and uiFocus
├── PerformClient.swift          # Routines --perform <plugin> <action> [text]
└── Views/
    ├── ActionGate.swift         # The one entry point for a press, with the native dialog
    ├── PluginView.swift         # The plugin page: header, banners, tabs
    ├── PluginUIView.swift       # The web view tab, the focus after ready, Reload
    ├── CollectionViews.swift    # InboxView and InboxRow
    └── Sidebar.swift            # The Inbox count and the count per plugin
app/Tests/RoutinesKitTests/
├── HostTests.swift              # ActionLookupTests
├── PluginUITests.swift          # PluginUIManifestTests, PluginUIBridgeTests
├── UnitTests.swift              # ExternalActionTests, ManifestTests, BoardStoreTests
├── NativeActionsGoneTests.swift # Only ActionGate calls the actions of the host
├── PluginUIWebKitTests.swift    # The hostile page in a real web view
└── Fixtures/                    # echo, ui-plugin, hostile-ui
packages/sdk/src/
├── host.ts                      # CardAction, Card, ActionEvent, PluginActionEvent, PluginDefinition
├── board.ts                     # DONE_ACTION_ID, onDoneAction, moveCard
└── testing.ts                   # manifestActions for tests of an action list
packages/ui/src/
├── bridge.ts                    # The typed bridge client, actionOf, imageUrl
├── context.tsx, hooks.ts        # PluginProvider, usePlugin, useSnapshot, mount, useFocus, useFocusedItem
├── markdown.ts                  # parseMarkdown, parseInline, previewOf
├── groups.ts, format.ts         # byState and the state names, timeAgo, shortDay
└── components/                  # ActionButton, DoneButton, Markdown, ItemBoard and the other controls
scripts/no-html.test.ts          # No HTML sink in packages/ui/src
workspace/scripts/build-plugins.ts # Builds dist/plugin.js and dist/ui of each plugin
```

**Structure Decision**: shared UI logic lives in `packages/ui`. Each plugin keeps its UI in `plugins/<id>/ui` of the repo or workspace that holds it.

## Complexity Tracking

No gate needs a reason.
