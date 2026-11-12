# Implementation Plan: Plugin UI in HTML and JavaScript

**Branch**: `002-plugin-ui` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-plugin-ui/spec.md`

## Summary

A plugin can ship a UI that the host shows in a `WKWebView` tab. The host serves the UI from the custom scheme `routines-ui`. A strict content policy, a content rule list, a navigation guard and a data store per web view keep the page inside its own bundle. A message bridge gives the page a snapshot of its own plugin, and the host sends a new snapshot after each change. The host decides each action call. It refuses an action that the manifest does not list, and it asks you first for an action with `confirm: true`.

`design/tokens.json` holds the colors, opacities, type, spacing, sizes, paddings, radii and shadows. A build script turns it into the Swift `Tokens` and the CSS of `packages/ui`, so the app and the plugin UIs share one style. `DESIGN.md` describes the tokens, the controls and the rules for plugin UIs. `packages/ui` gives Preact versions of the app controls and a typed bridge client. The Inbox lists the items of all plugins that need you, and a row opens the item in its plugin UI.

## Technical Context

**Language/Version**: Swift 6 for the host. TypeScript bundled by Bun 1.3 for plugins and plugin UIs.

**Primary Dependencies**: Apple frameworks only in the host: SwiftUI, AppKit, WebKit and JavaScriptCore. Preact 10 in `packages/ui`, bundled into each plugin UI. See [research.md](research.md), section 8.

**Storage**: The JSON stores in `~/Library/Application Support/Routines`. A card has an optional `data` field for its plugin UI.

**Testing**: `swift test` for the host. `bun test packages scripts` for `packages/ui`, the token build and the HTML rule. The WebKit security test runs only with `ROUTINES_WEBKIT_TESTS=1`.

**Target Platform**: macOS 15 or later.

**Project Type**: A desktop app with a plugin API.

**Performance Goals**: The web view shows at most 1 second after the load starts. An action answer reaches the page as soon as the handler returns.

**Constraints**: No network and no foreign files in a plugin UI. No color, font size or radius literal in the Swift views. No white frame before the first frame of a page.

**Scale/Scope**: The app ships with no plugins. One web view per open UI tab.

## Constitution Check

| Rule | Status | How the design keeps it |
| --- | --- | --- |
| R1. The host knows no routine | Pass | The host serves any `dist/ui` folder and names no plugin id. `HostIsGenericTests` covers the UI files too. |
| R2. Agents decide and code acts | Pass | The feature adds no node. A press calls the action handlers of the plugin. |
| R3. A plugin gets only what its manifest declares | Pass | A page reaches only its own items, page, actions and listed images. `PluginUIBridgeTests` and `PluginUIResourcesTests` cover each refusal. |
| R4. Errors are values | Pass | Each bridge answer is `{ ok: true, value }` or `{ ok: false, error }`. The client of `@routines/ui` returns a `Result` and does not throw. |
| R5. State survives a crash | Pass | The page holds no state of its own. The host stores stay the one source. |
| R6. The host owns the control surface | Pass | Each press comes from a plugin UI and goes through `ActionGate`. The host finds the action in the manifest and shows its own dialog for `confirm: true`. `NativeActionsGoneTests` fails on any other caller. |
| R7. Plain code over frameworks | Pass | The host uses WebKit, an Apple framework. Preact is a plugin UI dependency, with its reason in `research.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/002-plugin-ui/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    ├── plugin-ui.md     # Manifest field, build, page limits, bridge messages, host events, client
    └── tokens.md        # Token file format and the generated outputs
```

`scripts/build-workspace.ts` copies both contracts into `docs/` of the workspace of the threads.

### Source Code (repository root)

```text
DESIGN.md                                  # The design guide
design/tokens.json                         # The one token source
scripts/
├── build-tokens.ts                        # tokens.json -> Tokens.swift and tokens.css, with --check
├── build-tokens.test.ts
├── no-html.test.ts                        # No HTML sink in packages/ui/src
└── build-workspace.ts                     # Copies the contracts into the workspace docs
workspace/scripts/build-plugins.ts         # Builds ui/main.tsx into dist/ui with the fixed shell
app/Sources/RoutinesKit/
├── Model/Card.swift                       # CardAction.confirm and target, Card.data
├── Model/Manifest.swift                   # The ui field
├── Host/ActionLookup.swift                # Finds an action in the manifest and checks it
├── Stores/BoardStore.swift                # The 32 KB limit of data
└── UI/
    ├── PluginUIResources.swift            # Path rules of the scheme: bundle files and listed images
    ├── PluginUIScheme.swift               # WKURLSchemeHandler with the content policy header
    ├── PluginUIBridge.swift               # Decodes a message and decides the answer
    ├── PluginUISnapshot.swift             # The data that the page gets
    └── PluginWebView.swift                # WKWebView: rule list, data store, navigation guard, events
app/Sources/Routines/
├── AppModel.swift                         # Plugin tabs, the Inbox items, the item to focus
└── Views/
    ├── Tokens.swift                       # Generated from design/tokens.json
    ├── Theme.swift                        # Semantic names over Tokens
    ├── PluginView.swift                   # The plugin page: UI, Runs and Settings
    ├── PluginUIView.swift                 # Web view host, ready gate, snapshot push, focus
    ├── ActionGate.swift                   # The one entry point for a press, with the host dialog
    └── CollectionViews.swift              # The Inbox
app/Tests/RoutinesKitTests/
├── PluginUITests.swift                    # Manifest, resources and bridge decisions
├── PluginUIWebKitTests.swift              # Hostile page in a real web view
├── HostTests.swift                        # ActionLookupTests
├── TokenUseTests.swift                    # No style literals in the views
├── NativeActionsGoneTests.swift           # Only the gate calls an action
└── Fixtures/
    ├── ui-plugin/                         # A plugin with a UI and six actions
    └── hostile-ui/                        # The page of the WebKit security test
packages/ui/src/
├── tokens.css                             # Generated
├── base.css                               # Canvas, font, color-scheme, --accent
├── components.css                         # Styles of the controls and the page layout
├── components/                            # The shared controls
├── bridge.ts                              # Typed client of the bridge
├── context.tsx                            # PluginProvider, usePlugin, useSnapshot, mount
├── hooks.ts                               # Plugin state, useFocus, useFocusedItem
├── markdown.ts                            # Markdown to blocks and inline nodes
└── groups.ts, format.ts                   # Item groups by state, dates
```

**Structure Decision**: host logic that tests can reach is in `RoutinesKit/UI`. Only the SwiftUI glue and the dialog are in the app target. Each plugin UI lives next to its plugin in `ui/`, and the shared controls live in `packages/ui`.

## Complexity Tracking

No gate violation needs a reason.
