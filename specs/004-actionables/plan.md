# Implementation Plan: Actionables

**Branch**: `004-actionables` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-actionables/spec.md`

## Summary

The host stores each item of work as an actionable, with one owner, one shared lifecycle and a list of steps. Routine plugins declare the kinds and states that they handle and their transitions, each with a risk level. Source plugins create and update actionables through one shared poll on a small model each minute.

Each request becomes one `Trigger`. A pure `Policy` decides it, and a pure `RunLifecycle` starts or queues the run. Outward and destructive transitions ask in the routine thread unless the allow list in the Keychain holds them. A question stores its agent session, and your answer resumes it. After each call, a memory node with no tools writes entries, and nodes search them through a read-only MCP server in the app binary. Routine threads replace the Inbox. Old cards move into actionables once, and the board calls stay as an adapter.

## Technical Context

**Language/Version**: Swift 6 for the host. TypeScript bundled by Bun 1.3 for the SDK, the UI package and plugins.

**Primary Dependencies**: Apple frameworks only in the host, with Security for the Keychain. Zod and Preact in the packages, as today. No new package. See [research.md](research.md).

**Storage**: JSON files in `~/Library/Application Support/Routines`: one file per actionable, the source cursors, a daily decision log, memory and its queue. The allow list is a Keychain item. See [data-model.md](data-model.md).

**Testing**: `swift test` for the host, with a fake clock, a fake agent runner and an allow list vault in memory. `bun test packages scripts` for the SDK and the UI package. The memory eval on a real agent runs only with `ROUTINES_AGENT_EVALS=1`.

**Target Platform**: macOS 15 or later.

**Project Type**: A desktop app with a plugin API.

**Performance Goals**: A hand-off, an answer or a press starts its work within 5 seconds (SC-001). An outside item becomes an actionable and starts its routine within 90 seconds (SC-002).

**Constraints**: At most one poll agent call a minute in total (SC-003). No decision reads memory (SC-004). The host names no kind, transition or routine (FR-011). A crash loses no step and repeats no outward action (R5).

**Scale/Scope**: About 15 routines and a few thousand actionables on one Mac. The repo ships no plugins. Triage and Factory live in your workspace, and their move to actionables is workspace work after the host lands.

## Constitution Check

The check uses constitution 4.0.0, which this plan amends. Version 3.0.0 failed R6 for this feature, because the host did not own the items and the Inbox was the place to answer. The amendment is the next section.

| Rule | Status | How the design keeps it |
| --- | --- | --- |
| R1. The host knows no routine | Pass | Kinds, transitions and handlers come from manifests. The host has only its own step actions. `HostIsGenericTests` covers the new folders. |
| R2. Agents decide and code acts | Pass | The poll and memory nodes return JSON, and code checks it: `onPoll` of each source and the memory writer of the host. Outward work runs only in `onTransition`, after the policy. |
| R3. A plugin gets only what its manifest declares | Pass | The poll gets only the tools of `source.tools`. A plugin moves only the actionables that it owns. `PermissionCheck` refuses writes to the host files. |
| R4. Errors are values | Pass | Each new host call returns a `Result`. Each refusal is a `Refusal` value with one text. |
| R5. State survives a crash | Pass | One atomic file write per step. A cursor moves only after its items are stored. The memory queue is a file. |
| R6. The host owns the work and the control surface | Pass | As amended: one store, one entrance, routine threads. `PolicyTests`, `RoutineThreadTests`, `NativeActionsGoneTests` and `PluginUIBridgeTests`. |
| R7. Plain code over frameworks | Pass | A JSON Schema subset, a stdio MCP server and the Keychain item use Apple frameworks only. `Package.swift` stays without packages. |
| R8. Memory informs and never permits | Pass | The world of the policy has no memory. The memory node has no tool. The search server only reads. `RiskTests`. |

Post-design check: each gate still passes after Phase 1. The contracts add no host call that names a routine, and no path from memory to the allow list.

## Constitution amendment 4.0.0

This plan applied the amendment to `.specify/memory/constitution.md`.

R6 becomes "The host owns the work and the control surface". The host stores each actionable, with its owner, state and steps. A plugin moves only the actionables that it owns, and only by a transition of its manifest. Each request goes through one entrance and one policy, and each refusal has one text for each caller. A routine asks you in its own thread, and the threads replace the Inbox. The rules of today for the plugin UI, the manifest actions and the host dialog stay.

R8 is new: "Memory informs and never permits". A memory entry can change what a node decides. It cannot grant a permission, change an allow list or change a manifest. Only you change an allow list, in the app.

## Project Structure

### Documentation (this feature)

```text
specs/004-actionables/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    ├── actionables.md    # Manifest fields, plugin functions, host calls, snapshot, board adapter
    ├── entrance.md       # Callers, policy order, refusal texts, permission questions, routine threads, --perform
    ├── sources.md        # Source manifest, pollRequest and onPoll, one poll
    └── memory.md         # The memory node, the search server, the Memory view
```

`scripts/build-workspace.ts` copies the four contracts into `docs/` of the workspace of the threads.

### Source Code (repository root)

```text
app/Sources/RoutinesKit/
├── Actionables/                 # New feature folder
│   ├── Actionable.swift         # Actionable, State, Step, Question, Move
│   ├── ActionableStore.swift    # One file per actionable, the indexes, apply(step)
│   ├── KindSchema.swift         # The JSON Schema subset
│   ├── Handles.swift            # The table of kinds and states, and the load conflicts
│   ├── BoardAdapter.swift       # board.* and onAction of the plugins of today
│   └── Migration.swift          # Cards to actionables, once
├── Entrance/                    # New feature folder
│   ├── Trigger.swift            # Trigger, its sources and its work
│   ├── Policy.swift             # The pure decision, Refusal and its texts
│   ├── RunLifecycle.swift       # idle, running, queued
│   ├── Entrance.swift           # PluginHost.submit: decide, record, act
│   ├── DecisionLog.swift        # decisions/<day>.jsonl
│   └── AllowList.swift          # AllowListVault, the Keychain vault and the vault in memory
├── Polling/                     # New feature folder
│   ├── PollPlan.swift           # Joins the requests, splits the output (pure)
│   ├── Poller.swift             # Once a minute, the CLI call, the cursors
│   └── CursorStore.swift        # sources/<plugin>.json
├── Memory/                      # New feature folder
│   ├── MemoryEntry.swift
│   ├── MemoryStore.swift        # entries.json and pending.json
│   ├── MemorySearch.swift       # The pure ranking
│   ├── MemoryNode.swift         # The batch call with no tools, the checks of its output
│   └── MemoryServer.swift       # Routines --memory-mcp: stdio JSON-RPC, read only
├── Threads/RoutineThread.swift  # The derived routine thread
├── Threads/ThreadContext.swift  # Kind, state and external transitions in <routine-items>
├── Model/Manifest.swift         # handles, kinds, transitions, source
├── Host/PluginHost.swift        # Runs and actions through the entrance, the poll and memory timers
├── Host/ExternalAction.swift    # item
├── Runtime/Bridge.swift         # actionables.*, refusals for a source, runSoon as a trigger
├── Plugins/PermissionCheck.swift # The host files that plugins cannot write
├── Plugins/PluginCatalog.swift  # Reads dist/kinds.json, applies Handles.build
├── UI/PluginUIBridge.swift      # The transition message
└── UI/PluginUISnapshot.swift    # actionables, transitions, allowed
app/Sources/Routines/
├── AppModel.swift               # No Inbox. Routine threads, the question focus, notifications
├── PerformClient.swift          # --item
├── main.swift                   # --memory-mcp
└── Views/
    ├── ActionGate.swift         # A press of a transition submits a ui trigger
    ├── RoutineThreadView.swift  # New: open and answered questions, the reply field, the permission buttons
    ├── ThreadPanel.swift        # The Routines group
    ├── MemoryView.swift         # New: read, edit and delete entries
    ├── PluginSettingsView.swift # The allow list switches
    ├── Sidebar.swift            # No Inbox. The count of open questions. Memory
    └── CollectionViews.swift    # InboxView goes
app/Tests/RoutinesKitTests/
├── ActionableTests.swift        # ActionableStoreTests, KindSchemaTests, HandlesTests, MigrationTests
├── EntranceTests.swift          # PolicyTests, RunLifecycleTests, EntranceTimingTests, RiskTests
├── PollTests.swift              # PollPlanTests
├── MemoryTests.swift            # MemoryTests, and MemoryEvalTests behind ROUTINES_AGENT_EVALS
├── ThreadTests.swift            # RoutineThreadTests, ThreadContextTests
├── UnitTests.swift              # ExternalActionTests, ManifestTests, HostIsGenericTests
└── Fixtures/                    # A sender routine, an asking routine and a source
packages/sdk/src/
├── host.ts                      # Actionable types, actionables.*, onTransition, pollRequest, onPoll
├── actionables.ts               # New: move helpers, asks()
├── agent.ts                     # runNode with session and memory
├── poll.ts                      # New: definePoll
└── testing.ts                   # The fake actionable store and the fake poll
packages/ui/src/
├── bridge.ts                    # The transition message, the new snapshot fields
└── components/TransitionButton.tsx
workspace/scripts/build-plugins.ts # Writes dist/kinds.json from src/kinds.ts
scripts/build-workspace.ts       # Copies the new contracts
ARCHITECTURE.md                  # Actionables, the entrance, polling, memory, routine threads
```

**Structure Decision**: the host groups new code by feature, as `Threads/` and `Agent/` do today. `Actionables/`, `Entrance/`, `Polling/` and `Memory/` each hold their model, their store and their logic. Existing files change in place, and `BoardStore` goes after the migration.

## Order of work

1. The store, the states, the steps, the kinds and the handles table, with the migration and the board adapter (story 1).
2. The trigger, the policy, the run lifecycle and the decision log. Each caller of today moves to `submit` (story 2).
3. Questions, sessions in `runNode`, routine threads and the end of the Inbox (story 3).
4. Risk levels, the allow list and the permission questions (story 5).
5. Sources and the poll (story 4).
6. Memory, the search server and the Memory view (story 6).
7. `--perform --item` and the `<routine-items>` lines (story 7).
8. The constitution, `ARCHITECTURE.md` and the workspace docs. Then Triage and Factory in your workspace (SC-007).

## Complexity Tracking

| Choice | Why needed | Simpler option rejected because |
| --- | --- | --- |
| The board adapter | Thirteen plugins of your workspace use the board today. | A load error stops all of them on the day of the update. |
| The allow list in the Keychain | A thread agent in auto mode can edit each file in the data folder. | A protected file stops plugins only, not the thread agent. |
| A stdio MCP server in the app | FR-034 asks for a tool that cannot write. | A Bash rule matches a prefix, so text from a message can add a second command. |
