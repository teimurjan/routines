# Research: Actionables

Each section names a decision, the reason for it and the other options. The spec left no open question, so each section settles a design choice of the plan.

## 1. The store of actionables

Decision: the host keeps one JSON file per actionable in `actionables/` of the data folder, and it loads all of them at launch. The id of an actionable is a whole number as a string, for example `"9"`. The next id is in `actionables/next-id.json`. The store keeps an index by owner and an index by source and dedupe key in memory.

Rationale: a hand-off, a step or a source update then writes one small file with one atomic write (R5). A short number fits a command line: `--item 9`. The index makes FR-022 one lookup.

Alternatives considered: one file per owner, as the board does today. A hand-off then writes two files, and a crash between the writes loses the actionable or copies it. One file for all actionables. Each step then writes all of them.

## 2. The shape of a kind

Decision: the manifest names the kinds that a plugin declares, for example `"kinds": ["bug"]`. The build script of the workspace writes `dist/kinds.json` from the Zod schemas that `src/kinds.ts` exports, with `z.toJSONSchema`. `KindSchema` in the host checks data against a small subset of JSON Schema: `type`, `properties`, `required`, `items`, `enum`, `additionalProperties` and `maxLength`. Each kind has at most one declaration among the loaded plugins. A kind that no plugin declares accepts any JSON object up to 32 KB, as card data does today.

Rationale: FR-008 asks the host to refuse a hand-off with data that does not fit, so the host needs the shape. Zod stays the one source of the shape in the plugin, and the host reads the generated file. A subset validator is about 100 lines and needs no package (R7). The migrated kinds of FR-010 have no declaration, so they keep working.

Alternatives considered: a call of the receiving plugin that checks the data. The receiving plugin then decides a host rule, and a hand-off needs a second JavaScript context. A JSON Schema package. R7 forbids it, and the subset covers what `z.toJSONSchema` writes for the kinds of today.

## 3. Transitions and the work that they do

Decision: the manifest lists `transitions`. Each one has an id, a label, the states that it starts from, a risk level, and optionally `input`, `confirm` and `style`. The host calls `onTransition(event)` of the plugin only after the policy allows the trigger. The handler does the outward work and returns a move: the end state and the changes. The host applies the move as one step. In a run, a plugin calls `actionables.move` for a `read` or `reversible` transition, and `actionables.request` for the others. A request is a trigger with the source `self`.

Rationale: plugin code does each outward action (R2), so the risk check must come before the code runs, not at the record. The handler of an allowed trigger is the only place where an `outward` or `destructive` transition happens. A move in a run needs no second call for the safe transitions.

Alternatives considered: one `move` call for all risks, with the check at the record. The outward action then already happened. A grant token that a run asks for and spends later. It adds a second state that can leak between calls.

Limit: the host cannot see what a command does. A plugin that runs `gh pr merge` outside a transition handler breaks its contract. The `exec` list of the manifest still limits its commands (R3), and the review of each plugin checks that outward commands run only in handlers.

## 4. Hand-off by kind and state

Decision: `actionables.handoff(id, { state, kind?, data?, title? })` names the new state and the new kind, not a routine. The host finds the one routine that handles that kind and state, and makes it the owner in one step. It refuses three cases: no routine handles the pair, the handler is the same routine, or the data does not fit the kind.

Rationale: FR-009 makes the handler of each kind and state unique, so the pair names the routine. A plugin then names no other plugin, and a routine can change without a change to its senders.

Alternatives considered: a `to` field with a routine id. Two routines then depend on the ids of each other, and the host checks the same thing twice.

## 5. One trigger and one policy

Decision: each caller builds one `Trigger` value with the routine, the source, the work and the optional actionable, transition and text. The sources are `clock`, `ui`, `self`, `routine`, `external`, `answer` and `source`. The work is `run` or `transition`. `Policy.decide(trigger, world)` is a pure function. `world` holds the manifests, the blocker of each routine, the actionable, the allow list and the run lifecycle state. It returns one `Decision`. The refusal texts are cases of one `Refusal` enum, so each caller gets the same words (FR-015, SC-005).

Rationale: one pure function covers each rule in a test without a JavaScript context. The world has no memory field, so no memory entry can change a decision (FR-036). The type system then holds the rule, and a test checks the signature.

Alternatives considered: checks in each caller, as today. The UI, `runSoon` and `--perform` then drift, as the slow approval of the spec shows.

## 6. The run lifecycle

Decision: `RunLifecycle` is a pure state machine per routine with three states: `idle`, `running` and `queued`. A run trigger in `idle` starts a run at once. A run trigger in `running` moves to `queued`. A run trigger in `queued` merges and keeps `queued`. The end of a run in `queued` starts the next run. Transition triggers keep the serial queue of each plugin that actions use today, so a long run does not delay an answer.

Rationale: FR-016 names the three states. A run starts within the time of one JavaScript context, which is far below 5 seconds (FR-017). `runSoon` becomes a run trigger with the source `self` and a delay.

Alternatives considered: a short debounce before each run. It adds delay to each hand-off, and the `queued` state already merges a burst.

## 7. The decision log

Decision: each decision appends one line to `decisions/<day>.jsonl`, with the trigger, the decision and the reason. The host keeps 14 days. If the reason of a blocked routine did not change since its last refusal, the refusal adds no line (US2-5). A run or a transition call still writes its run record and its log file, and the record names the trigger.

Rationale: a poll each minute and the clock make many decisions, and the run index keeps only 500 records. A line per decision is cheap to append and to read in a test.

Alternatives considered: a run record for each decision. The records of real runs then drop out of the index within a day.

## 8. One poll for all sources

Decision: a source plugin declares `source` in its manifest, with its kinds and the read-only connector tools that it needs. Once a minute, the host calls `pollRequest({ cursor })` of each source that is on. Each one returns a prompt, an input and a JSON Schema. `PollPlan` joins them into one prompt with a section per source and one output schema with a key per source. The host runs one `claude -p` call on the `haiku` model. The call has `--setting-sources user`, `--permission-mode dontAsk` and `--json-schema`. Its `--allowedTools` is the union of the declared tools. Then it calls `onPoll({ cursor, output })` of each source with its part of the output. The handler checks the part with Zod and returns the items and the new cursor. The host stores the items, and only then it saves the cursor (FR-021).

Rationale: one call a minute meets FR-020 and SC-003 for any number of sources. If no source is on, no call runs. The poll node reads text from other people. It thus gets only the read tools of the manifests, and plugin code checks its output (R2).

Alternatives considered: one call per source. The cost then grows with each source. A poll node that a plugin runs. A plugin cannot run on behalf of other plugins without a new host permission.

Details: a poll that runs longer than 50 seconds ends with a failure, and the next poll waits until the current one ends. A failed poll keeps each cursor. The page of a source shows the failure once and clears it after the next good poll. Each poll writes its log to `runs/polls/<day>.log`, not to the run index.

## 9. Risk and consent

Decision: a `read` or `reversible` transition applies without a question. For an `outward` or `destructive` transition, two sources count as your consent for that one trigger: a press in the app (`ui`) and your answer in a routine thread (`answer`). Each other source needs the transition in the allow list of the routine. Without it, the host moves the actionable to `waiting-on-you` and posts a permission question in the routine thread, with Allow once, Always allow and Deny. A transition with `confirm: true` starts only from `ui`, after the host dialog (FR-025).

Rationale: a press on Approve is already your decision, so a second question in a thread adds nothing. FR-014 lets FR-024 and FR-025 name the source, and these two sources are the only ones that you start yourself.

Alternatives considered: a question for each outward transition, also after a press. You then answer twice for one decision.

Deny moves the actionable back to its state before the question, in a host step. Always allow adds the transition to the allow list and then works as Allow once.

## 10. Where the allow list lives

Decision: the allow list is one item in the Keychain of your login, which only the app reads and writes without a prompt. `AllowListVault` is a protocol, and the tests use a vault in memory. The Settings tab of a routine lists its `outward` and `destructive` transitions with a switch each.

Rationale: plugins can write the data folder today, and a thread agent in auto mode can edit any file there. A Keychain item of the app asks you before another process reads or changes it. This meets FR-026 without a new mechanism of the host. Security is an Apple framework (R7).

Alternatives considered: a field in `settings.json`, with the path protected from plugins. A thread agent can still write it. An HMAC over a file with a key in the Keychain. It needs the Keychain anyway and adds a second file.

## 11. Questions and agent sessions

Decision: a move can carry a question with its text, the transition that the answer starts, and the agent session: its id and its working folder. The host then forces the state `waiting-on-you` and stores the question in the step. The SDK adds `runNode(task)`, which returns the output and the session id. It passes `--session-id <new UUID>` for a new session and `--resume <id>` to continue one. Your answer is a trigger with the source `answer`. The host calls `onTransition` with the answer text and the stored session. If the CLI cannot resume the session, `runNode` starts a new one. The input of the new session holds the answer and the step history, and the run log says so.

Rationale: the session id is in the step file, so it survives a quit of the app (US3-4). The SDK picks the session id, so the host knows it before the CLI ends. This also holds for a call that fails. `claude --help` of version 2.1.323 lists `--session-id`, `--resume`, `--json-schema` and `--restricted` together. The quickstart checks a resume with a JSON Schema on the real CLI.

Alternatives considered: the session id from the `session_id` field of the CLI result. A call that times out then has no id.

## 12. Routine threads

Decision: a routine thread is not a stored chat. `RoutineThread.build(routine, actionables)` derives it from the steps of the actionables that the routine owns: each question step and the answer step after it. An open question is an actionable in `waiting-on-you` whose last step asks. Actionables with no owner form the No owner thread. An answer goes through the entrance. A refusal shows under the question in the thread, and the decision log keeps it.

Rationale: one record, the steps, then holds the questions and the answers. The thread cannot disagree with the state of the actionable, which is the bug of today (US3).

Alternatives considered: a thread file per routine. It copies each question. If a script moves the actionable, the copy goes stale.

## 13. Memory

Decision: memory is one file, `memory/entries.json`. When a run or a transition call ends, the host queues its new steps in `memory/pending.json`. One memory call at a time takes up to 20 pending steps. It runs `claude -p` on `haiku` with `--restricted`, `--strict-mcp-config`, `--tools ""` and `--json-schema`, so it has no tool at all. The host writes the entries that it returns, each with its type, text, tags, routine and step. A failed call keeps the steps in the queue, and the run log names the failure (US6-5).

Rationale: the node writes only through its JSON output, and host code writes the file (FR-037). A queue that survives a quit loses no step. A batch keeps the cost near one call per run.

Alternatives considered: one call per step. A poll that updates many actionables then makes many calls. A node with a write tool. If a crafted step asks for it, the node can then write outside memory.

## 14. The memory search tool

Decision: the app binary is a small stdio MCP server: `Routines --memory-mcp --routine <id>`. It has one tool, `search`, with a query, optional tags and a limit. It reads `memory/entries.json` and never writes. `MemorySearch` ranks by the overlap of words and tags, and it returns at most 8 entries and 4,000 characters. It searches the entries of that routine. `runNode` with `memory: true` adds `--strict-mcp-config`, `--mcp-config` with this server, and `mcp__routines-memory__search` to the allowed tools. With `--strict-mcp-config`, `--restricted` keeps the servers of `--mcp-config`.

Rationale: FR-034 asks for a tool, and the binary is already the tool guard. A server with one read tool cannot write, edit or delete (US6-3). JSON-RPC over stdio for three methods needs no package.

Alternatives considered: a Bash command for the search. Bash rules match a prefix, so text from a message can add a second command. Memory in the input of each node. The node then gets entries that it did not ask for, and the input grows.

## 15. Host files that plugins cannot write

Decision: the data folder stays allowed for each plugin, but `PermissionCheck` refuses a write to the host files in it. These are `actionables/`, `memory/`, `decisions/`, `board/` and `settings.json`. Reads stay allowed.

Rationale: a plugin must change actionables only through the bridge, so the owner check and the step record cannot be skipped (FR-004, FR-003).

## 16. Old cards and old plugins

Decision: at the first launch, `Migration` moves each `board/<plugin>.json` into actionables once. The owner and the kind are the plugin id, the source is the plugin id, and the dedupe key is the old card id. The state comes from the column, by the map in the spec. The host renames the file to `<plugin>.json.migrated`. The `board.*` host calls stay as an adapter for plugins that still use them: `board.upsert` finds the actionable by source and key, and a new column is a step with the actor of the plugin. Item actions of a manifest still call `onAction`, and the adapter treats them as `outward` transitions from each open state.

Rationale: thirteen plugins in your workspace use the board today. They keep working while you move each one, and an item action keeps its behavior of today: it starts only from a press. FR-010 asks for exactly this map.

Alternatives considered: a load error for each old manifest. All plugins then stop on the day of the update.

## 17. External requests

Decision: `Routines --perform <routine> <transition> --item <id> [text]` names an actionable. `ExternalAction` gets an optional `item`. The trigger has the source `external`. The policy checks `permissions.external`, the owner, the start state, `confirm` and the risk (FR-027). The `<routine-items>` block of a thread turn lists, for each item, the transitions that `permissions.external` allows now from its state (US7-3).

Rationale: the thread agent and a script then use the same entrance and the same refusal texts as a press.

## 18. The Inbox goes

Decision: the sidebar loses the Inbox. The thread panel gets a Routines group with one row per routine and its count of open questions. A notification of a question carries the routine id and the step id, and a click opens that question in the routine thread. The sidebar count of a routine is its open questions.

Rationale: FR-032 and the amended R6. One place to answer.

## 19. Tests of the rules

Decision: each rule has a named test.

| Test | What it covers |
| --- | --- |
| `ActionableStoreTests` | Steps, owner checks, dedupe, the files and the reload |
| `KindSchemaTests` | The subset of JSON Schema, and refused hand-off data |
| `HandlesTests` | The table of kinds and states, and the load conflict of FR-009 |
| `PolicyTests` | Each decision and each refusal, equal for each source |
| `RunLifecycleTests` | The three states and the merge of triggers |
| `EntranceTimingTests` | A fake clock: a hand-off, an answer and a press start within 5 seconds |
| `PollPlanTests` | One call for three sources, the cursor rules, a failed poll |
| `RiskTests` | Each risk level with an empty and a full allow list, and a memory entry that claims a permission |
| `RoutineThreadTests` | Open and answered questions, two questions, a stale answer |
| `MemoryTests` | The search, the read-only server, edits and deletes, a failed memory call |
| `MigrationTests` | Cards to actionables, once |
| `HostIsGenericTests` | No kind, transition or routine id in the host (R1) |

`packages/sdk` tests `runNode` arguments, the fake actionable store of `testing.ts` and the kinds build. The memory eval of SC-006 runs on the real agent, by the quickstart.

## 20. The move of Triage and Factory

Decision: a new source plugin, `slack-mentions`, polls your DMs, group DMs and mentions in the shared poll. It keeps only the messages that ask for a code change, older than 10 minutes, and makes one `slack-message` per permalink. Triage handles `slack-message` in `new`. One node per run checks your replies and reactions, then hands each task to `bug` in `new` or drops it. Triage keeps its own scan twice an hour for the answers to Factory, the review requests and the promises, so Review and Promises need no change. Factory handles `bug` in `new` and `ready`, and the actionable is its only record. Its issue ledger, its backlog, its own jobs and the security probe are gone, because a routine cannot create an actionable.

Rationale: you chose these three options when the move began. A routine that creates its own items would need a new host call, and a second record next to the actionable would drift from it.

Details: the transition `route` posts the "queued" reply in Slack, so it is `outward`. Factory asks you before each one until you allow `route` in its Settings tab. A worker question keeps its checkout and its agent session, so your answer continues there. A fix in another repo moves the same bug to that repo. A step for you, or a job with no clear repo, asks you in the routine thread.

Two findings changed the SDK. The API refuses an output schema without `type: object` at its root, so `asks(schema)` returns `{ question, result? }` and not a union. `definePoll` passes the run context and accepts an async `input`, so a source reads its settings and its first cursor. The host now also checks the data of a move against its kind.
