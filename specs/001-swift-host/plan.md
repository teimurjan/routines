# Implementation Plan: Swift host with JavaScript plugins

**Branch**: `001-swift-host` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-swift-host/spec.md`

## Summary

A SwiftUI app hosts each routine as a plugin. A plugin is a TypeScript bundle that runs in a new JavaScriptCore context for each call. It reaches the Mac only through the host calls that its manifest allows. The app runs plugins on clock slots, sends actions to them and lists the work that needs you in the Inbox. A thread runs a coding agent that makes plugins in the workspace of the app.

## Technical Context

**Language/Version**: Swift 6 for the host and the app. TypeScript on Bun for the SDK, the UI controls, the prelude and the build scripts.

**Primary Dependencies**: SwiftUI, JavaScriptCore, WebKit, CoreServices (FSEvents), UserNotifications and ServiceManagement in the host. Zod in the SDK, Preact in the UI controls and core-js in the prelude.

**Storage**: JSON files in the data folder of the app. Plugin state in `~/.local/state/routines`.

**Testing**: `swift test` for the host, `bun test packages scripts` for the packages and the scripts.

**Target Platform**: macOS 15 or later.

**Project Type**: A desktop app with a plugin runtime.

**Constraints**: The host has no package dependencies (R7). Plugin code has no Node and no Bun APIs. The host source names no plugin (R1).

**Scale/Scope**: One person and one Mac.

## Constitution Check

| Rule | How the plan satisfies it |
| --- | --- |
| R1 | Plugins come from folders, and the app ships none. If a host source names the id of a folder in `plugins/` at the repo root, `HostIsGenericTests` fails. |
| R2 | `runAgent` sends the Zod output schema of each node and parses the result with it. Plugin code does the outward actions. |
| R3 | `PermissionCheck` checks each command, host, path, browser call and activity read against the manifest. |
| R4 | Each host call returns a `Result`. The runtime turns a thrown error into a failed call. |
| R5 | `readStateFile` returns an error for a file that does not parse. `BoardStore` does not write over a cards file that does not parse. |
| R6 | The manifest lists each action, and `ActionGate` is the one entry point of a press in the app. |
| R7 | `Package.swift` has no dependencies. |

## Project Structure

### Documentation (this feature)

```text
specs/001-swift-host/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/plugin-api.md
```

`bun run build:workspace` copies `contracts/plugin-api.md` into the workspace as `docs/plugin-api.md`.

### Source Code (repository root)

```text
app/                          The Swift package
├── Sources/RoutinesKit/      The host. It has no routine code (R1).
│   ├── Model/                Manifest, Card, Page, Activity, JSONValue
│   ├── Plugins/              PluginCatalog, PermissionCheck
│   ├── Runtime/              PluginRuntime (JavaScriptCore), Bridge, HostServices, Prelude
│   ├── Services/             Exec, File, HTTP, Lock and Browser (WebKit)
│   ├── Stores/               Board, Notes, Settings, Notifications, Pages, Runs
│   ├── Schedule/             Clock slots and the due check
│   ├── Host/                 PluginHost, ActionLookup, ExternalAction, ToolGuard, HostPaths
│   ├── UI/                   The scheme, the web view and the bridge of plugin UIs
│   ├── Agent/                The thread CLIs: command, process, stream, health
│   ├── Threads/              ThreadService, ThreadStore, ThreadContext
│   └── Workspace/            Workspace install, FolderWatcher
├── Sources/Routines/         The SwiftUI app: sidebar, Inbox, Threads, Runs, plugin pages
└── Tests/RoutinesKitTests/   Host tests and fixture plugins
packages/
├── sdk/                      Host API types, runAgent, state files, queues, card helpers, test host
├── ui/                       Preact controls, tokens CSS and the bridge client of plugin UIs
└── prelude/                  The web APIs for JavaScriptCore
workspace/                    AGENTS.md, CLAUDE.md, package.json and the plugin build script of the threads
scripts/                      build-prelude, build-tokens, build-workspace, typecheck, bundle-app.sh
```

**Structure Decision**: the host is a library, so tests drive it without the app. The packages are Bun workspaces. The repo holds no plugins.

## Process model

Each call of a plugin gets a new JavaScriptCore context on its own serial queue. The host evaluates the prelude and then the bundle. The prelude builds the `routines` global over one native function, `__native.call(method, json)`, which returns a promise. The bridge decodes the request, checks it and does the work. Then it resolves the promise with the JSON of a `Result`, on the queue of the context.

One `run` of a plugin runs at a time. The actions of a plugin run one after another, but they do not wait for a run. A call that passes `timeoutMinutes` fails. The host then frees its locks and closes its browser pages.

The scheduler checks the clock slots every 20 seconds and after each wake. It skips the checks while the Mac sleeps. One or more slots in the time since the last check start one run, so a Mac that slept runs each plugin once. The look-back is at most 2 days.

The binary has two more modes. With `--tool-guard`, it is the `PreToolUse` hook of guarded agent tools. With `--perform`, it asks the running app for an external plugin action through a `routines://` URL and prints the answer from a reply file.

A thread turn runs the Claude Code or Codex CLI in the workspace, with the prompt on stdin. The host turns each JSON line of output into thread events. At launch, the host compares the `version.txt` of the workspace source with the installed one. If they differ, it copies the source into the workspace. An FSEvents watcher on the plugin folders in the data folder reloads the catalog. A change of a manifest, a build or a plugin folder starts the reload.

## Complexity Tracking

| Choice | Why | Simpler choice and why not |
| --- | --- | --- |
| A new context for each call | A call cannot leak state into the next call, and a hung call does not block the next one. | One context per plugin keeps state across runs, and one hung promise holds it. |
| WebKit for the browser | WebKit is part of macOS and is a real browser engine. | A headless Chromium needs Node and a download. |
| The `external` manifest list | Any program can open a `routines://` URL. | Accepting each action lets any web page or script press it. |
| The app binary as the tool guard | The guard then needs no Bun and no extra file. | A separate script adds a runtime to each agent node. |
