---
description: "Task list for the actionables feature"
---

# Tasks: Actionables

**Input**: Design documents from `specs/004-actionables/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The spec gives an independent test for each story, and the constitution names a check for each rule. Each story phase thus starts with its tests. Write them first, and make sure that they fail before the code exists.

**Organization**: The tasks are grouped by user story, so each story can be built and tested alone.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: The task can run in parallel. It changes other files and needs no open task.
- **[Story]**: The user story of the task, for example US1.
- Paths are relative to the repo root. `Kit/` is short for `app/Sources/RoutinesKit/`, `App/` for `app/Sources/Routines/`, and `Tests/` for `app/Tests/RoutinesKitTests/`.

---

## Phase 1: Setup

**Purpose**: Test seams and fixtures that each story uses.

- [X] T001 Add `AgentRunner` in `Kit/Agent/AgentRunner.swift`: `public typealias AgentRunner = @Sendable (_ args: [String], _ stdin: String, _ cwd: String, _ timeout: Duration) async -> Result<String, HostError>`. Add `AgentRunner.cli(home:)`, which runs the command with `AgentProcess` and returns stdout. The poll and the memory node use it, and tests pass a fake.
- [X] T002 Add the parameters `now: @escaping @Sendable () -> Date = Date.init` and `runAgent: AgentRunner = .cli(home:)` to `PluginHost.init` in `Kit/Host/PluginHost.swift`. Keep each current caller working with the defaults.
- [X] T003 [P] Add `FakeClock` (a settable `now`) and `FakeAgent` (records each call and returns queued answers) to `Tests/Support.swift`. Add `Fixture.actionablePaths()`, which returns `paths()` with `Fixtures/actionables` as the only plugin folder.
- [X] T004 [P] Create the fixture routine `sender` in `Tests/Fixtures/actionables/sender/` with `plugin.json`, `dist/plugin.js` and `dist/kinds.json`. It handles `note` in `new` and `ready`, and it declares `note`. Its transitions are `start` (from `new` and `ready`, `reversible`) and `send` (from `working`, `outward`). Its `run` hands each `working` actionable to kind `bug` in state `new` with the data `{ "repo": "demo", "details": "x" }`. Write the JavaScript by hand, as the `echo` fixture does.
- [X] T005 [P] Create the fixture routine `asker` in `Tests/Fixtures/actionables/asker/`. It handles `bug` in `new` and declares `bug` with `required: ["repo", "details"]` and `additionalProperties: false`. It has four transitions. `answer` starts from `waiting-on-you`, is `reversible` and has `input`. `merge` starts from `working` and is `destructive`. `approve` starts from `waiting-on-you`, is `outward` and has `confirm: true`. `drop` starts from `new`, `ready` and `waiting-on-you`, and is `reversible`. `permissions.external` lists `answer` and `drop`. Its `run` moves each `new` bug to `waiting-on-you` with a question `{ text: "Which key?", transition: "answer", session: { id: "s-1", cwd: "/tmp" } }`. Its `onTransition` for `answer` returns `{ to: "working", status: <the text> }` and logs the session id.
- [X] T006 [P] Create the fixture source `notes-source` in `Tests/Fixtures/actionables/notes-source/` with `source: { kinds: ["note"], tools: ["mcp__fake__read"] }`. Its `pollRequest` returns a prompt, the cursor as input and the schema `{ items: [{ key, title }] }`. Its `onPoll` maps each item to `{ dedupeKey: key, kind: "note", title, data: {} }` and returns the cursor `{ after: <last key> }`.

---

## Phase 2: Foundational

**Purpose**: The types and the store that each story needs. No story starts before this phase ends.

- [X] T007 [P] Create `Kit/Actionables/Actionable.swift` with the types of [data-model.md](data-model.md). `State` has the eight raw values of the data model. Its `isClosed` is true for `done`, `failed` and `dropped`. Add `State(column:)` and `column` by the map of the data model: `new` maps to `planned`, `waiting-on-others` to `working`, and `dropped` to `done`. `Actionable` has each field of the table, and `data` is a `JSONValue` object. `Step.Action` encodes as `transition:<id>`, `handoff`, `created`, `updated`, `asked`, `answered`, `denied`, `board` or `migrated`. Add `Question`, `Session { id, cwd }` and `Move`.
- [X] T008 [P] Add `handles: [Handle]`, `kinds: [String]`, `transitions: [TransitionDeclaration]` and `source: SourceDeclaration?` to `Kit/Model/Manifest.swift`, each with an empty default. `TransitionDeclaration` has `id`, `label`, `from: [State]`, `risk: Risk` (`read`, `reversible`, `outward`, `destructive`), `input`, `confirm` and `style`. Add `role`: `.source` with `source`, `.routine` with `handles` or `transitions`, else `.legacy`.
- [X] T009 [P] Create `Kit/Entrance/Trigger.swift` with `Trigger` of the data model. `Source` has `clock`, `ui`, `self`, `routine`, `external`, `answer` and `source`. `Work` has `run` and `transition`. `Grant` has `once` and `always`. Add `legacyName` for the `trigger` string of `RunContext`: clock is `schedule`, self is `soon`, ui is `action`, and each other source keeps its name.
- [X] T010 Create `Kit/Actionables/ActionableStore.swift`, a `@MainActor @Observable` store on `actionables/` of the data folder. Load each `<id>.json` at init. Keep an index by owner and an index by `source` and `dedupeKey`. Take ids from `actionables/next-id.json`, a whole number as a string. Each change writes one file with one atomic write. A file that does not parse goes to `errors`, and the store never writes over it. Refuse `data` over "At most 32 KB as JSON". Prune closed actionables by the retention days of the owner, as `BoardStore.pruned` does. Give `create`, `append(step:changes:)`, `actionable(_:)`, `owned(by:)`, `past(of:)` and `find(source:key:)`. Depends on T007.
- [X] T011 Add the write guard to `Kit/Plugins/PermissionCheck.swift`. A new `protected: [String]` list holds `actionables/`, `memory/`, `decisions/`, `board/` and `settings.json` of the data folder. `writablePath(_:)` refuses each of them with `the host owns <path>`. Use it in the `fs.writeText`, `fs.writeBase64`, `fs.remove` and `fs.mkdir` routes of `Kit/Runtime/Bridge.swift`. Reads stay as they are.
- [X] T012 [P] Add the actionable types of [contracts/actionables.md](contracts/actionables.md) to `packages/sdk/src/host.ts`. `StoredActionable` has `readOnly`. `RunContext` has `trigger: string`, `source` and `actionable?`.
- [X] T013 Write `ActionableStoreTests` in `Tests/ActionableTests.swift`. One step writes one file. A reload gives equal actionables. A corrupt file stays on disk and blocks writes to it. A second create with the same source and key is refused. Data over 32 KB is refused. A closed actionable goes after its retention. Add a test to `PermissionTests` in `Tests/UnitTests.swift`: a plugin with the data folder in its paths cannot write `actionables/1.json` but can read it.

**Checkpoint**: The store works, and the manifest decodes the new fields.

---

## Phase 3: User Story 1, all routines share one model of work (Priority: P1) 🎯 MVP

**Goal**: The host stores each actionable, records each step, checks the owner and the transition, and hands work from one routine to another.

**Independent Test**: Load `sender` and `asker`. Create a `note` for `sender`, move it through three states, and hand it to `asker` as a `bug`. Read the store and the steps.

### Tests for User Story 1

- [X] T014 [P] [US1] Write `KindSchemaTests` in `Tests/ActionableTests.swift`. Cover `type`, `properties`, `required`, `items`, `enum`, `additionalProperties: false` and `maxLength`. A schema with another keyword, for example `pattern`, is refused. An undeclared kind accepts any object.
- [X] T015 [P] [US1] Write `HandlesTests` in `Tests/ActionableTests.swift`. Two routines that handle `bug` in `new` give a problem to the second in catalog order (FR-009). A kind that two plugins declare gives a problem. A missing `dist/kinds.json` entry gives a problem. A manifest with `source` and `transitions` gives a problem. A transition with an empty `from` gives a problem.
- [X] T016 [P] [US1] Write `MoveTests` in `Tests/ActionableTests.swift`, one per acceptance scenario of US1. Owner moves `ready` to `working` adds one step. Another owner is refused with no step. An unlisted transition and a wrong start state are refused with the texts `<routine> has no transition <transition>` and `<transition> does not start from <state>`. A hand-off changes the owner in one `handoff` step with `oldOwner` and `oldKind`. A hand-off with data that does not fit `bug` is refused. A hand-off that no routine handles is refused, and the owner stays.
- [X] T017 [P] [US1] Write `MigrationTests` in `Tests/ActionableTests.swift`. Two board files become actionables with the plugin as owner, kind and source, the card id as dedupe key, and the state from the column. Each gets a `migrated` step. The files become `<plugin>.json.migrated`. A second launch migrates nothing.
- [X] T018 [P] [US1] Write `SnapshotTests` in `Tests/PluginUITests.swift`. The snapshot of `asker` holds only its owned actionables and the past ones with `readOnly: true`. Each has `allowed` with the transitions from its state. `items` holds the owned ones in the card shape.

### Implementation for User Story 1

- [X] T019 [P] [US1] Create `Kit/Actionables/KindSchema.swift`. Parse a schema into a value that knows only `type`, `properties`, `required`, `items`, `enum`, `additionalProperties` and `maxLength`. Refuse another keyword at parse time. `validate(_ value: JSONValue) -> Result<Void, HostError>` names the path of the first fault, for example `data.repo must be a string`.
- [X] T020 [US1] Read `dist/kinds.json` in `Kit/Plugins/PluginCatalog.swift` for each name in `manifest.kinds`. Keep the parsed schemas on `PluginEntry.kinds`. Give a problem for a missing or bad schema, and for rules 3, 4 and 5 of the manifest list in [contracts/actionables.md](contracts/actionables.md). Depends on T019.
- [X] T021 [US1] Create `Kit/Actionables/Handles.swift`. `Handles.build(_ entries: [PluginEntry]) -> (table: [HandleKey: String], kinds: [String: KindSchema], problems: [String: String])`, in catalog order. Apply it in `PluginHost.reload` and set each problem on its entry.
- [X] T022 [US1] Create `Kit/Actionables/MoveCheck.swift` with pure checks. `move(_:by:actionable:manifest:)` checks the owner, the declared transition, the start state, an end state in the lifecycle, and a risk of `read` or `reversible`. `handoff(_:by:actionable:handles:kinds:)` checks the owner, one handler for the new kind and state, a handler other than the sender, and the data against the kind. Return the refusal texts of [contracts/entrance.md](contracts/entrance.md).
- [X] T023 [US1] Add `apply(move:transition:actor:trigger:)` and `handoff(...)` to `ActionableStore` in `Kit/Actionables/ActionableStore.swift`. Each runs the check of T022 and appends exactly one step with `from`, `to`, `outcome`, `actor` and `trigger`. A hand-off appends `pastOwners`.
- [X] T024 [US1] Add the routes `actionables.list`, `actionables.get`, `actionables.move` and `actionables.handoff` to `Kit/Runtime/Bridge.swift`, and the store access to `Kit/Runtime/HostServices.swift`. `list` with `past: true` adds the past ones with `readOnly: true`. A plugin with the role `.source` gets `a source cannot move an actionable` for `move` and `handoff`.
- [X] T025 [US1] Create `Kit/Actionables/Migration.swift`. At `PluginHost.start`, before the first run, move each `board/<plugin>.json` into actionables by the rules of T017. Map the card fields `body`, `status`, `tags`, `links`, `images`, `date`, `progress` and `data` to the same fields.
- [X] T026 [US1] Create `Kit/Actionables/BoardAdapter.swift` for plugins with the role `.legacy`. `upsert(card)` finds the actionable by the plugin and the card id, or creates it. A new column appends a `board` step. `remove` moves it to `dropped`. `list` returns the owned ones in the card shape. Route `board.upsert`, `board.remove` and `board.list` of `Kit/Runtime/Bridge.swift` to it.
- [X] T027 [US1] Remove `BoardStore` from `Kit/Host/PluginHost.swift`. Point `resolveAction`, `perform`, `activity`, `itemContext` and the status line of an action to the store and the adapter. Delete `Kit/Stores/BoardStore.swift` and move its tests in `Tests/UnitTests.swift` to the adapter.
- [X] T028 [US1] Add `actionables`, `transitions` and `allowed` to `Kit/UI/PluginUISnapshot.swift` by [contracts/actionables.md](contracts/actionables.md). Build `items` from the owned actionables in the card shape. Keep only the actionables that the routine owns or owned (FR-012).
- [X] T029 [P] [US1] Add `routines.actionables.list`, `get`, `move` and `handoff` to `RoutinesHost` in `packages/sdk/src/host.ts` and to the prelude calls in `packages/prelude/src/index.ts`.
- [X] T030 [P] [US1] Create `packages/sdk/src/actionables.ts` with `moveTo(id, transition, to, changes?)` and `handTo(id, change)`, which return the `Result` of the host. Export it from `packages/sdk/src/index.ts`.
- [X] T031 [P] [US1] Add a fake actionable store to `packages/sdk/src/testing.ts`. It has the owner and transition checks of the host, so plugin tests can move actionables. Test it in `packages/sdk/src/actionables.test.ts`.
- [X] T032 [P] [US1] Write `dist/kinds.json` in `workspace/scripts/build-plugins.ts`. Import `src/kinds.ts` of each plugin that has it, and write `z.toJSONSchema` of each export by name, without `$schema`. Test it in `scripts/build-kinds.test.ts`.
- [X] T033 [US1] Update `App/AppModel.swift`, `App/Views/Sidebar.swift` and `App/Views/PluginUIView.swift` for the removal of `host.board`. They read the store or the snapshot.

**Checkpoint**: Story 1 works alone. Plugins of today keep their cards through the adapter.

---

## Phase 4: User Story 2, work starts at once after a hand-off, an answer or a request (Priority: P1)

**Goal**: Each caller builds one trigger. One pure policy decides it, and one run lifecycle starts or queues the run.

**Independent Test**: With a fake clock, hand an actionable from `sender` to `asker` and count the seconds to the run of `asker`. Send one trigger from each caller and compare the records.

### Tests for User Story 2

- [X] T034 [P] [US2] Write `RunLifecycleTests` in `Tests/EntranceTests.swift`. Cover each arrow of the diagram in [data-model.md](data-model.md). Three run triggers during a run leave one queued run.
- [X] T035 [P] [US2] Write `PolicyTests` in `Tests/EntranceTests.swift`. One test per check of the order in [contracts/entrance.md](contracts/entrance.md), and one per refusal text. One trigger from `ui`, `external` and `self` gets equal decisions and equal text (SC-005). A test reads the stored properties of `Policy.World` with `Mirror`. If one holds memory, the test fails.
- [X] T036 [P] [US2] Write `EntranceTimingTests` in `Tests/EntranceTests.swift`. With `FakeClock` and the fixtures, a hand-off, an answer and a press each start their work within 5 seconds of the trigger. A blocked routine gets one decision line for two equal refusals in a row.
- [X] T037 [P] [US2] Write `DecisionLogTests` in `Tests/EntranceTests.swift`. Each decision adds one line with the trigger, the decision and the reason. Files older than 14 days go.

### Implementation for User Story 2

- [X] T038 [P] [US2] Create `Kit/Entrance/RunLifecycle.swift`: `enum RunLifecycle { case idle, running, queued }` with a pure `next(on: Event) -> (RunLifecycle, Effect?)`. The events are `trigger` and `ended`. The effects are `start` and `none`.
- [X] T039 [US2] Create `Kit/Entrance/Policy.swift`. `Refusal` has the cases and the texts of [contracts/entrance.md](contracts/entrance.md). `World` holds the manifests, the handles table, the blocker of each routine, the actionable, the allow list and the lifecycle state, and nothing else. `decide(_ trigger: Trigger, _ world: World) -> Decision` runs checks 1 to 7 and 9 in order. Check 8 passes each risk for now. Story 5 adds it. Depends on T038.
- [X] T040 [P] [US2] Create `Kit/Entrance/DecisionLog.swift`. Append `{ id, at, trigger, decision, reason? }` as one JSON line to `decisions/<yyyy-mm-dd>.jsonl`. Delete files older than 14 days at launch. Keep the last refusal reason of each routine, and skip an equal refusal of a blocked routine.
- [X] T041 [US2] Create `Kit/Entrance/Entrance.swift` with `PluginHost.submit(_ trigger: Trigger) -> Decision`. Build the world, decide, log, and act. `startRun` and `queueRun` drive the lifecycle of the routine. `callTransition` queues `onTransition` in the action queue of the plugin and applies the returned `Move` through `ActionableStore.apply`. A failed handler adds no step and sets `status` to `Error: <reason>`. The run record names `trigger.legacyName`.
- [X] T042 [US2] Move each caller of `Kit/Host/PluginHost.swift` to `submit`. `tick` submits `clock` triggers. `requestRun` submits a `self` run trigger after the delay. `start` with `runAtLaunch` submits a `clock` trigger. Remove `runNow`, `startRequestedRun`, `skip` and `requestedRuns`.
- [X] T043 [US2] Submit a `routine` run trigger for the new owner after each hand-off in the `actionables.handoff` route of `Kit/Runtime/Bridge.swift`.
- [X] T044 [US2] Add the route `actionables.request` to `Kit/Runtime/Bridge.swift`. It submits a `self` transition trigger and returns `queued` or `asked`, or the refusal. Add it to `packages/sdk/src/host.ts` and `packages/prelude/src/index.ts`.
- [X] T045 [US2] Add the page message `{ type: "transition", actionable, transition, text? }` to `Kit/UI/PluginUIBridge.swift`. Decide `.confirm` for `confirm: true` and `.perform` otherwise, with the label and the stored title.
- [X] T046 [US2] Change `App/Views/ActionGate.swift` so a transition press submits a `ui` trigger after the dialog. Plugin actions and legacy item actions also submit `ui` triggers. Update `Tests/NativeActionsGoneTests.swift`: only `ActionGate` submits `ui` triggers.
- [X] T047 [P] [US2] Add the `transition` message and the snapshot fields to `packages/ui/src/bridge.ts`. Create `packages/ui/src/components/TransitionButton.tsx`, which reads the declaration by id, shows its label, style and input, and is disabled while pending. Export it from `packages/ui/src/components/index.ts`. Test the message in `packages/ui/src/bridge.test.ts`.
- [X] T048 [P] [US2] Pass `trigger`, `source` and `actionable` in `RunContext` from `Kit/Host/PluginHost.swift`, and type them in `packages/sdk/src/host.ts`.

**Checkpoint**: Each caller goes through `submit`. A hand-off starts the next routine within seconds.

---

## Phase 5: User Story 3, a routine asks you in its own thread (Priority: P1)

**Goal**: A node returns a question, the routine thread shows it, and your answer resumes the agent session.

**Independent Test**: Run `asker`. Read its routine thread. Answer, then read the state, the steps and the session id of the next node call.

### Tests for User Story 3

- [X] T049 [P] [US3] Write `RoutineThreadTests` in `Tests/ThreadTests.swift`. A move with a question gives one open question with the actionable title. Two open questions and one answer move only that actionable. An answer after the actionable left `waiting-on-you` gets `actionable <id> no longer waits on you`. A second answer to one question gets `this question was already answered`. Actionables with no owner form the No owner thread.
- [X] T050 [P] [US3] Write `SessionTests` in `Tests/ThreadTests.swift`. An answer calls `onTransition` with the stored `session` and the `history` since the last answer. After a new host loads the same data folder, the answer passes the same session.
- [X] T051 [P] [US3] Test `runNode` in `packages/sdk/src/agent.test.ts`. A new session passes `--session-id` with a UUID. A resume passes `--resume <id>` with the stored `cwd`. A failed resume runs once more with a new session, logs `the session <id> did not resume, so a new session started`, and passes the history.

### Implementation for User Story 3

- [X] T052 [US3] Check a move with a question in `Kit/Actionables/MoveCheck.swift`. The question text has "1 to 2,000 characters". Its transition "starts from `waiting-on-you` and has `input`". Force `to` to `waiting-on-you`. A question has `transition` or `permission`, never both.
- [X] T053 [US3] Create `Kit/Threads/RoutineThread.swift` with the pure `RoutineThread.build(routine:actionables:)`, which returns `open`, `answered` and `count` by [data-model.md](data-model.md).
- [X] T054 [US3] Handle the source `answer` in `Kit/Entrance/Policy.swift` (check 7) and in `Kit/Entrance/Entrance.swift`. Append an `answered` step with your text. Then call `onTransition` with your text, the `session` of the question step, and the `history` since the last answer.
- [X] T055 [P] [US3] Add `runNode` and `asks(schema)` to `packages/sdk/src/agent.ts` by [contracts/actionables.md](contracts/actionables.md). Read `session_id` of the CLI result. Keep `runAgent` as it is.
- [X] T056 [US3] Add the routine thread state to `App/AppModel.swift`: the selected routine thread, `answer(_ text:, question:)` and `open(question:)`. `answer` submits the trigger and keeps the refusal text for the view. Remove `SidebarItem.inbox`, `needsYou` and the Inbox branch of `open(pluginId:cardId:)`.
- [X] T057 [US3] Create `App/Views/RoutineThreadView.swift`. Show the open questions first, each with the actionable title, the question and a reply field. Show the refusal under its question. Then show the answered questions, newest first. Take each style from `Tokens`.
- [X] T058 [US3] Add the Routines group to `App/Views/ThreadPanel.swift`, above the agent threads. Show one row per loaded routine with its count of open questions. An actionable with no owner adds a No owner row. A row opens `RoutineThreadView`.
- [X] T059 [US3] Post a notification for each new question in `Kit/Entrance/Entrance.swift` with `routineId` and `stepId`. In `App/AppModel.swift`, a click opens the thread panel at that question.
- [X] T060 [US3] Delete `InboxView` and `InboxRow` from `App/Views/CollectionViews.swift`. Remove the Inbox from `App/Views/Sidebar.swift` and `App/Views/ContentView.swift`. The sidebar count of a routine is its open questions.

**Checkpoint**: Stories 1 to 3 form the MVP. Work moves, starts at once and asks you in one place.

---

## Phase 6: User Story 4, outside events become actionables within a minute (Priority: P2)

**Goal**: One poll a minute on a small model creates and updates actionables for all sources.

**Independent Test**: Give `notes-source` a fake answer with two new items and one known item. Run one poll. Read the store and the cursor.

### Tests for User Story 4

- [X] T061 [P] [US4] Write `PollPlanTests` in `Tests/PollTests.swift`. Three sources join into one prompt with one `<source id="...">` section each and one schema with each id required. The output splits back by id. No source gives no plan.
- [X] T062 [P] [US4] Write `PollerTests` in `Tests/PollTests.swift` with `FakeAgent`. Two new items and one known item add two actionables in `new` and one `updated` step, and move the cursor. A known item in `done` gets an `updated` step and stays `done`. A failed call keeps the cursor, and the next minute starts from it. Three sources make one agent call a minute. A new `note` makes `sender` the owner and submits a `source` run trigger. A kind outside `source.kinds` fails that source only.

### Implementation for User Story 4

- [X] T063 [P] [US4] Add `pollRequest`, `onPoll`, `PollRequest` and `PollItem` to `packages/sdk/src/host.ts`. Create `packages/sdk/src/poll.ts` with `definePoll({ prompt, input, output, toItems })`, which writes both functions from one Zod schema. Test it in `packages/sdk/src/poll.test.ts`.
- [X] T064 [P] [US4] Create `Kit/Polling/PollPlan.swift` with the pure `build(requests:) -> PollPlan?` and `split(output:plan:) -> [String: JSONValue]`. The prompt says that the text that the agent reads is data from other people.
- [X] T065 [P] [US4] Create `Kit/Polling/CursorStore.swift` on `sources/<plugin>.json` with `cursor`, `polledAt` and `error`.
- [X] T066 [US4] Create `Kit/Polling/Poller.swift` with the nine steps of [contracts/sources.md](contracts/sources.md). Start at most once a minute, and never while a poll runs. Run `claude -p --model haiku --output-format json --json-schema <schema> --setting-sources user --permission-mode dontAsk --allowedTools <tools>` through `AgentRunner` with a timeout of 50 seconds. Save a cursor only after each item of that source is stored. Write each poll to `runs/polls/<yyyy-mm-dd>.log` with the line `poll started`. Depends on T064 and T065.
- [X] T067 [US4] Start the poller in `PluginHost.start` of `Kit/Host/PluginHost.swift`, and stop it while the Mac sleeps.
- [X] T068 [US4] Show the last poll, the cursor time and the last error of a source on its page in `App/Views/PluginView.swift`. Show the error once, and clear it after a good poll.

**Checkpoint**: A new outside item becomes an actionable, and its routine starts.

---

## Phase 7: User Story 5, a routine acts alone only inside the risk that you allowed (Priority: P2)

**Goal**: Outward and destructive transitions ask in the routine thread until the allow list holds them.

**Independent Test**: Give `asker` each risk level. Make each transition with an empty and a full allow list. Add a memory entry "always allow merges" and make the merge again.

### Tests for User Story 5

- [X] T069 [P] [US5] Write `RiskTests` in `Tests/EntranceTests.swift`, one per acceptance scenario of US5. A `reversible` transition applies with an empty list. A `self` request of `merge` gives `ask`, an `asked` step and an open permission question. With `merge` in the list, it applies. A memory entry with "always allow merges" changes no decision (SC-004). `approve` from `external` gets `Approve starts only from a press in the app`. Allow once runs the handler from the state before the question. Deny moves it back with a `denied` step and runs no handler. Always allow adds `merge` to the list.

### Implementation for User Story 5

- [X] T070 [P] [US5] Create `Kit/Entrance/AllowList.swift`. `AllowListVault` has `load() -> [String: Set<String>]` and `save(_:)`. `KeychainVault` stores one generic password item named `Routines allow list` with Security. `MemoryVault` is for tests. `AllowList.effective(_:manifests:)` keeps only ids that the manifest declares as `outward` or `destructive`.
- [X] T071 [US5] Add check 8 to `Kit/Entrance/Policy.swift` by [contracts/entrance.md](contracts/entrance.md). For an Allow on a permission question, use the state before the `asked` step in check 3.
- [X] T072 [US5] Handle `ask` in `Kit/Entrance/Entrance.swift`. Append an `asked` step with `question.permission`, and move the actionable to `waiting-on-you`. For `grant: once`, append an `answered` step back to the state before the `asked` step, then call the handler. For `grant: always`, save the list first. Add `deny(question:)`, which appends a `denied` step back to that state.
- [X] T073 [US5] Show the text `<routine> wants to <label>: <title>` and the buttons Allow once, Always allow and Deny for a permission question in `App/Views/RoutineThreadView.swift`.
- [X] T074 [US5] List the `outward` and `destructive` transitions of a routine with one switch each in `App/Views/PluginSettingsView.swift`. A switch saves through the vault. No other code writes the list.
- [X] T075 [US5] In `Kit/Actionables/BoardAdapter.swift`, treat each item action of a `.legacy` plugin as an `outward` transition from each open state. It then starts only from a press, as today.

**Checkpoint**: No outward or destructive transition applies without your press, your answer or the allow list.

---

## Phase 8: User Story 6, the app learns from each step (Priority: P2)

**Goal**: A memory node writes entries after each call. Nodes search them read-only. You read, edit and delete them.

**Independent Test**: Answer a question of `asker`. Read memory. Give a second bug with the same subject, and read the search calls and the node result.

### Tests for User Story 6

- [X] T076 [P] [US6] Write `MemoryTests` in `Tests/MemoryTests.swift` with `FakeAgent`. After a call ends, its steps go to `pending.json`. An answer step gives an entry of type `answer` linked to its step. An entry with an unknown step, an unknown type or text over 1,000 characters is refused. A failed memory call keeps the steps and logs the failure. A step that fails three times leaves the queue. `MemorySearch` ranks by words and tags, with ties broken by the newer entry, and returns at most 8 entries and 4,000 characters. An edited entry returns its new text, and a deleted one is gone.
- [X] T077 [P] [US6] Write `MemoryServerTests` in `Tests/MemoryTests.swift`. `initialize` and `tools/list` return the one `search` tool of [contracts/memory.md](contracts/memory.md). `tools/call` of `search` returns the entries of the routine only. Each other method and each other tool gets a JSON-RPC error, and the file is unchanged.
- [X] T078 [P] [US6] Write `MemoryEvalTests` in `Tests/MemoryTests.swift`, enabled only with `ROUTINES_AGENT_EVALS=1`. Run the case of quickstart section 6 ten times on the real CLI, and pass with 9 or more.

### Implementation for User Story 6

- [X] T079 [P] [US6] Create `Kit/Memory/MemoryEntry.swift` with the fields of [data-model.md](data-model.md). `type` is `answer`, `outcome`, `fact` or `preference`. `text` has "1 to 1,000 characters". `tags` has "At most 8, lowercase".
- [X] T080 [US6] Create `Kit/Memory/MemoryStore.swift` on `memory/entries.json` and `memory/pending.json` with `enqueue(steps:)`, `take(20)`, `write(entries:)`, `edit(id:text:tags:)` and `delete(id:)`. Keep a failure count per pending step.
- [X] T081 [P] [US6] Create `Kit/Memory/MemorySearch.swift` with the pure ranking of [contracts/memory.md](contracts/memory.md).
- [X] T082 [US6] Create `Kit/Memory/MemoryNode.swift`. Build the input of step 3 of [contracts/memory.md](contracts/memory.md). Run `claude -p --model haiku --output-format json --json-schema <schema> --restricted --strict-mcp-config --tools ""` through `AgentRunner`. Check and write the entries, and set `routine` to the owner at the time of the step. Run one call at a time.
- [X] T083 [US6] At the end of each run and each transition call, enqueue its new steps in `Kit/Entrance/Entrance.swift`. Then start the memory node.
- [X] T084 [US6] Create `Kit/Memory/MemoryServer.swift`, a stdio JSON-RPC 2.0 server for `initialize`, `tools/list` and `tools/call`. It opens `memory/entries.json` read-only for each call and has no method that writes. Add the `--memory-mcp --routine <id>` branch to `App/main.swift`, before the app starts.
- [X] T085 [P] [US6] Add `memory: true` to `runNode` in `packages/sdk/src/agent.ts`. It adds `--strict-mcp-config`, the `--mcp-config` of [contracts/memory.md](contracts/memory.md) with `host().info.appCommand`, and `mcp__routines-memory__search` to the allowed tools. Test the arguments in `packages/sdk/src/agent.test.ts`.
- [X] T086 [US6] Create `App/Views/MemoryView.swift` with the entries, newest first, a search field, and filters by routine and type. You can edit the text and the tags, and delete an entry. Each entry links to its actionable. Add a Memory item to `App/Views/Sidebar.swift`.

**Checkpoint**: Memory fills after each call, and nodes find your earlier answers.

---

## Phase 9: User Story 7, a thread agent or a script moves an actionable (Priority: P3)

**Goal**: `--perform` with `--item` uses the same entrance and the same policy as a press.

**Independent Test**: From a test, perform a listed transition with an item, an unlisted transition, and a transition with `confirm: true`. Read the replies and the store.

### Tests for User Story 7

- [X] T087 [P] [US7] Extend `ExternalActionTests` in `Tests/UnitTests.swift`. A URL with `item` round-trips. `answer` of `asker` with `--item` applies in `waiting-on-you`. `merge` gets `asker does not allow merge from outside the app`. `approve` gets `Approve starts only from a press in the app`. An actionable of another routine gets `asker does not own actionable <id>`.
- [X] T088 [P] [US7] Write `ThreadContextTests` in `Tests/ThreadTests.swift`. Each `<item>` has the lines `Kind:`, `State:` and `External transitions now:` with the transitions that `permissions.external` lists and the state allows.

### Implementation for User Story 7

- [X] T089 [US7] Add `item` to `Kit/Host/ExternalAction.swift`, in `url` and in `parse`. With `item`, `PluginHost.performExternal` in `Kit/Host/PluginHost.swift` submits an `external` transition trigger and replies with the status of the move, or `Error: <refusal text>`.
- [X] T090 [US7] Parse `--item <id>` in `App/PerformClient.swift`. Update the usage line to `usage: Routines --perform <routine> <transition-or-action> [--item <id>] [text]`.
- [X] T091 [US7] Give `ItemContext` the actionable in `Kit/Threads/ThreadContext.swift`. Add three lines to each item: the kind, the state and the external transitions of now.

**Checkpoint**: Each story works alone, through one entrance.

---

## Phase 10: Polish and cross-cutting concerns

- [X] T092 [P] Extend `HostIsGenericTests` in `Tests/UnitTests.swift` to the four new folders of `Kit/`. It also fails on each kind and transition id of the plugins in `ROUTINES_PLUGINS_DIR` (FR-011).
- [X] T093 [P] Rewrite the Terms, the host diagram, the Inbox and the Threads sections of `ARCHITECTURE.md`. Describe actionables, the entrance, polling, memory and routine threads.
- [X] T094 [P] Add the four contracts of `specs/004-actionables/contracts/` to `DOCS` in `scripts/build-workspace.ts`, and describe actionables, transitions and `runNode` in `workspace/AGENTS.md`.
- [X] T095 Run `bun run check` from the repo root and fix each failure.
- [ ] T096 Run sections 3 to 5 of `specs/004-actionables/quickstart.md` and record each result in the pull request.
- [X] T097 Move Triage to actionables in `~/Library/Application Support/Routines/workspace/plugins/triage`. A new source plugin `slack-mentions` reads Slack. Triage handles `slack-message` in `new` and hands each task to `bug` in `new`.
- [X] T098 Move Factory to actionables in `~/Library/Application Support/Routines/workspace/plugins/factory`. It handles `bug` in `new` and `ready`, and declares its transitions with risk levels. Its `approve` and `reject` keep `confirm: true`. Its nodes ask through `runNode` and `asks`. Then run section 6 of the quickstart (SC-006, SC-007).

---

## Dependencies and execution order

### Phase dependencies

- Setup (Phase 1) has no dependency.
- Foundational (Phase 2) needs Setup, and it blocks each story.
- US1 (Phase 3) needs Phase 2.
- US2 (Phase 4) needs US1, because the entrance applies moves and hand-offs.
- US3 (Phase 5) needs US2, because an answer is a trigger.
- US4 (Phase 6) needs US2. It can run beside US3.
- US5 (Phase 7) needs US3, because a permission question shows in the routine thread.
- US6 (Phase 8) needs US3 for answer steps. It can run beside US4 and US5.
- US7 (Phase 9) needs US2. It can run beside US3 to US6.
- Polish (Phase 10) needs each story. T097 and T098 need T095.

### Within each story

- Write the tests first, and make sure that they fail.
- Models come before the store, the store before the bridge, and the bridge before the views.
- A task that names "Depends on" waits for that task.

### Parallel opportunities

- T003 to T006 in Setup.
- T007, T008, T009 and T012 in Phase 2.
- The tests of each story, which are all marked [P].
- In US1: T019, T029, T030, T031 and T032.
- In US2: T038, T040, T047 and T048.
- After US2: US3, US4 and US7 on separate branches. After US3: US5 and US6.

---

## Parallel example: User Story 1

```text
Task: "Write KindSchemaTests in Tests/ActionableTests.swift"
Task: "Write HandlesTests in Tests/ActionableTests.swift"
Task: "Write MigrationTests in Tests/ActionableTests.swift"
Task: "Write SnapshotTests in Tests/PluginUITests.swift"

Task: "Create Kit/Actionables/KindSchema.swift"
Task: "Add routines.actionables calls to packages/sdk/src/host.ts and packages/prelude/src/index.ts"
Task: "Write dist/kinds.json in workspace/scripts/build-plugins.ts"
```

The four test tasks write one file, `Tests/ActionableTests.swift`, except `SnapshotTests`. If two agents write them at once, give each test struct its own file first.

---

## Implementation strategy

### MVP first

1. Complete Phase 1 and Phase 2.
2. Complete US1, then run `swift test --filter 'ActionableStoreTests|KindSchemaTests|HandlesTests|MoveTests|MigrationTests|SnapshotTests'`.
3. Stop, and check that the plugins of today still show their cards through the adapter.

### Incremental delivery

1. US1: one store and one step list.
2. US2: one entrance. Hand-offs start work at once.
3. US3: routine threads replace the Inbox. This ends the MVP.
4. US4, US5 and US6: sources, risk and memory.
5. US7: scripts and thread agents.
6. Polish, then Triage and Factory in your workspace.

---

## Notes

- Each task ends with `bun run check` green for the files that it touched.
- Commit after each task or each group of tasks.
- No task names a plugin id in `app/Sources` (R1).
