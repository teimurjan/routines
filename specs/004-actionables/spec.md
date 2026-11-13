# Feature Specification: Actionables

**Feature Branch**: `004-actionables`

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Actionables: a host-owned, event-driven loop for routines. Replace per-plugin cards with host-stored actionables (kind, source, one owner routine at a time, state, typed data, steps). All actionables share one lifecycle: new, ready, working, waiting on you, waiting on others, done, failed, dropped. A step is one state change, and the host records each step with its trigger and outcome. Two plugin kinds: source plugins create or update actionables from outside systems through one shared Haiku poll node every minute, with a cursor and a dedupe key. Routine plugins declare which kinds and states they handle and which transitions they can make, each with a risk level. One entrance: every trigger becomes one Trigger value, checked by one pure policy and fed to a pure run lifecycle. Hand-offs, answers and requests start work within seconds, and outside events within a minute. Outward and destructive transitions ask until allowed in an allow list that memory cannot change. A routine asks its questions in its own thread, and the answer continues the agent session. After each step, a memory node writes answers, outcomes, facts and preferences. Nodes search memory read-only, and memory never grants a permission."

## Terms

| Term | Meaning |
| --- | --- |
| Actionable | One item of work that the host stores. It replaces the card of each plugin. |
| Kind | The type of an actionable, for example `slack-message` or `bug`. A kind names the shape of its data. |
| Owner | The one routine that can move an actionable now. |
| State | The place of an actionable in the shared lifecycle. |
| Step | One state change of an actionable, with its trigger, its actor and its outcome. |
| Transition | A named state change that a routine declares in its manifest, for example `approve`. |
| Source plugin | A plugin that only creates and updates actionables from an outside system. |
| Routine plugin | A plugin that only moves the actionables that it owns. |
| Trigger | One request to start a run or a transition, from any caller. |
| Risk level | The effect of a transition outside the app: `read`, `reversible`, `outward` or `destructive`. |
| Allow list | The transitions of `outward` or `destructive` risk that you allow a routine to make without a question. |
| Routine thread | The one thread of a routine, where it asks you its questions. |
| Memory | The entries that the host keeps after each step: your answers, outcomes, facts and preferences. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - All routines share one model of work (Priority: P1)

Each item of work is an actionable that the host stores. Every actionable has a kind, a source, one owner, a state, typed data and a list of steps. All actionables use one lifecycle: `new`, `ready`, `working`, `waiting-on-you`, `waiting-on-others`, `done`, `failed` and `dropped`. When a routine moves an actionable, the host records the step. The UI of a routine shows the actionables that it owns, and the history of each one.

**Why this priority**: the other stories need one shared record. Today each plugin keeps its own cards, so the host cannot hand work from one routine to another.

**Independent Test**: load two fixture routines. Create an actionable for the first one, move it through three states, and hand it to the second one. Read the store and the step list.

**Acceptance Scenarios**:

1. **Given** an actionable in `ready`, **When** its owner moves it to `working`, **Then** the host adds one step (FR-003).
2. **Given** an actionable of another owner, **When** a routine asks to move it, **Then** the host refuses and adds no step.
3. **Given** an unlisted transition or a wrong start state, **When** a routine asks for it, **Then** the host refuses and names the reason.
4. **Given** an owned actionable, **When** its routine hands it to a routine that handles it, **Then** the owner changes in one step.
7. **Given** a hand-off that changes the kind, **When** the new data does not fit the new kind, **Then** the host refuses the hand-off.
5. **Given** a hand-off to a routine that does not handle it, **When** the host gets it, **Then** the host refuses, and the owner stays.
6. **Given** the plugin UI of a routine, **When** it opens, **Then** the snapshot holds only the actionables of FR-012, with steps.

---

### User Story 2 - Work starts at once after a hand-off, an answer or a request (Priority: P1)

Every caller reaches the host through one entrance. The callers are the clock, a plugin UI, `runSoon`, a hand-off, your answer, a thread agent, a script and a source. The host turns each one into a trigger and decides it with one policy. Each caller gets the same queue, the same record and the same reason for a refusal. A hand-off from Triage starts Factory within seconds, not at the next clock slot.

**Why this priority**: today Factory waits up to 30 minutes after Triage files a bug, and an approval waited for the next slot until a recent fix.

**Independent Test**: in a host test with a fake clock, hand an actionable from one fixture routine to another. Count the seconds to the start of the run of the second routine. Send the same trigger from each kind of caller and compare the records.

**Acceptance Scenarios**:

1. **Given** an idle routine, **When** another routine hands an actionable to it, **Then** its run starts within 5 seconds.
2. **Given** a routine with a run in progress, **When** three triggers arrive, **Then** exactly one more run follows the current run.
3. **Given** one request from three callers, **When** the host decides, **Then** all three get the same decision and text.
4. **Given** a trigger that the policy refuses, **When** the host decides it, **Then** no run starts, and the record names the reason.
5. **Given** a blocked routine, **When** a trigger arrives, **Then** no run starts, and its page shows the reason only once.

---

### User Story 3 - A routine asks you in its own thread (Priority: P1)

When a routine needs you, the actionable moves to `waiting-on-you`. The question appears in the thread of that routine, in a Routines group of the thread panel. You answer there. Your answer is a trigger, and the node that asked continues its agent session with your answer and its earlier context.

**Why this priority**: you rarely want to decide. When you decide, you want one place to answer. Today an answer in a thread never reaches the card, and the ticket stays in "Needs you".

**Independent Test**: run a fixture routine whose node asks a question. Read the routine thread. Answer it, and read the state, the step list and the agent session id of the next node call.

**Acceptance Scenarios**:

1. **Given** a node that returns a question, **When** the step ends, **Then** the actionable waits on you, and the thread shows the question.
2. **Given** a question in a routine thread, **When** you answer it, **Then** the node continues its agent session within 5 seconds.
3. **Given** two open questions in one routine thread, **When** you answer one, **Then** only the actionable of that question moves.
4. **Given** the app quits while a question is open, **When** the app starts again and you answer, **Then** the node continues the same agent session.
5. **Given** an answer, **When** the step ends, **Then** memory holds your answer, linked to that step.

---

### User Story 4 - Outside events become actionables within a minute (Priority: P2)

A source plugin reads one outside system, for example Slack, Gmail or Linear, through the Claude connectors. The host polls all sources once a minute, with one shared poll call on a small model. Each source keeps a cursor and gives each item a dedupe key. A new item creates an actionable, and a changed item updates it. The routine that handles the new actionable starts at once.

**Why this priority**: outside events start most of the work, but your company does not allow webhooks. Polling once a minute is the fastest path that is available.

**Independent Test**: give a fixture source a fake connector answer with two new items and one known item. Run one poll. Read the store and the cursor.

**Acceptance Scenarios**:

1. **Given** two new items and one known item, **When** a poll ends, **Then** the store adds two, updates one and moves the cursor.
2. **Given** an item with a dedupe key that the store already has, **When** a poll returns it again, **Then** no second actionable appears.
3. **Given** three source plugins, **When** one minute passes, **Then** the host makes at most one poll agent call in total.
4. **Given** a poll that fails, **When** the next minute comes, **Then** the poll starts again from the old cursor, and no item is lost.
5. **Given** a new actionable that a routine handles, **When** the host stores it, **Then** that routine owns it and starts within 5 seconds.

---

### User Story 5 - A routine acts alone only inside the risk that you allowed (Priority: P2)

Each transition in a manifest has a risk level. A routine makes a `read` or `reversible` transition without a question. For an `outward` or `destructive` transition, it asks you in its thread until you add that transition to its allow list. Memory can make a routine sure of a decision, but it can never add to the allow list.

**Why this priority**: memory comes from text that other people wrote, for example Slack messages. A crafted message must not be able to make a routine post, merge or delete alone.

**Independent Test**: give a fixture routine one transition of each risk level. Make each one with an empty allow list, then with a full allow list. Write a memory entry that says "always allow merges", then make the merge again.

**Acceptance Scenarios**:

1. **Given** an empty allow list, **When** a routine makes a `read` or `reversible` transition, **Then** the host applies it.
2. **Given** an empty allow list, **When** a routine makes an `outward` transition, **Then** the actionable waits on you, and the thread asks.
3. **Given** a transition in the allow list, **When** the routine makes it, **Then** the host applies it without a question.
4. **Given** a memory entry that claims a permission, **When** the routine makes an unlisted `outward` transition, **Then** the thread still asks you.
5. **Given** a transition with `confirm: true`, **When** a thread agent or a script asks for it, **Then** the host refuses it. Only a press in the app can start it.

---

### User Story 6 - The app learns from each step (Priority: P2)

After each step, a memory node on a small model reads the step and its outcome. It writes your answers, the outcomes, facts and preferences into memory. Each entry links to its step. Nodes get a read-only tool that searches memory. You can read, edit and delete each entry. Over time, routines find more answers in memory and ask you less often.

**Why this priority**: a routine that asks the same question twice wastes your time, and a routine that forgets a rejected fix repeats it.

**Independent Test**: answer a question of a fixture routine. Read memory. Give a second actionable of the same kind and subject to the routine, and read the search calls and the result of its node.

**Acceptance Scenarios**:

1. **Given** a step ends, **When** the memory node finishes, **Then** each new entry links to that step and names its type: answer, outcome, fact or preference.
2. **Given** an answer in memory, **When** a node of the same routine meets the same question, **Then** its memory search finds that answer.
3. **Given** a node, **When** it calls the memory tool, **Then** it can search, but it cannot write, edit or delete.
4. **Given** an entry that you edit or delete, **When** a node searches next, **Then** it gets your version, or nothing.
5. **Given** a memory node that fails, **When** the step ends, **Then** the step stays recorded, and the failure shows in the run log.

---

### User Story 7 - A thread agent or a script moves an actionable (Priority: P3)

A thread agent or a script names a routine, an actionable and a transition, for example `Routines --perform factory answer --item 9 "use the staging key"`. The host decides it through the same entrance and the same policy as a press in the app.

**Why this priority**: today a thread agent cannot move a card. Each routine needs its own glue code for that, or the work stays stuck.

**Independent Test**: from a test, perform a listed transition with an item, an unlisted transition, and a transition with `confirm: true`. Read the replies and the store.

**Acceptance Scenarios**:

1. **Given** a transition in `permissions.external`, **When** a script performs it in a valid state, **Then** the host applies it and replies.
2. **Given** a transition that `permissions.external` does not list, **When** a script performs it, **Then** the host refuses it.
3. **Given** a `<routine-items>` block in a thread turn, **When** the agent reads it, **Then** the block names the external transitions that each actionable allows now.

### Edge Cases

- A routine that owns actionables is deleted or fails to load. Its actionables stay in the store with no owner. The Routines group lists them in a No owner thread.
- Two routines declare that they handle the same kind and state. The host refuses to load the second manifest and names the conflict.
- A hand-off arrives while the receiving routine has a run in progress. The run lifecycle queues one more run.
- A source returns an item that the store holds in `done`. The host updates its data and adds a step, but it does not open it again. The owner decides.
- You answer a question after the actionable left `waiting-on-you`, for example after a script moved it. The host refuses the answer and says so in the thread.
- A node asks for a session that the agent CLI cannot resume. The host starts a new session with your answer and the step history, and the run log says so.
- The poll call fails for many minutes. The source shows the failure on its page once, and it keeps the old cursor.
- Memory grows large. A search returns the closest entries first, and the host keeps a limit on the size of each result.

## Requirements *(mandatory)*

### Functional Requirements

#### Actionables

- **FR-001**: The host MUST store each actionable with the fields of the Actionable entity under Key Entities.
- **FR-002**: The state of an actionable MUST be one of `new`, `ready`, `working`, `waiting-on-you`, `waiting-on-others`, `done`, `failed` or `dropped`.
- **FR-003**: Each state change MUST add exactly one step with the transition, the trigger, the actor, the time and the outcome.
- **FR-004**: Only the owner of an actionable MUST be able to make a transition of it.
- **FR-005**: A routine manifest MUST declare the kinds and states that it handles, and each transition that it can make. Each transition MUST name the states that it starts from and its risk level.
- **FR-006**: The host MUST refuse a transition that the manifest does not list or that does not start from the current state. The routine MUST choose the end state, and the host MUST refuse an end state outside the lifecycle.
- **FR-007**: A hand-off MUST change the owner to a routine that handles the kind and the state of the actionable. It MUST be one step.
- **FR-008**: A hand-off MUST keep the same actionable and its steps. A hand-off can also change the kind and the data, for example from `slack-message` to `bug`. The new data MUST fit the shape of the new kind, and the step MUST record the old kind.
- **FR-009**: The host MUST refuse to load a manifest that handles a kind and state that another loaded routine already handles.
- **FR-010**: The host MUST move the stored cards of each plugin into actionables once, with the plugin as owner and the plugin id as kind.
- **FR-011**: The code of the host MUST NOT name a kind, a transition or a routine (R1).
- **FR-012**: The snapshot of a plugin UI MUST hold only the actionables that its routine owns, and the actionables that it owned before, read-only.

#### One entrance

- **FR-013**: The host MUST turn each request into one trigger with the fields of the Trigger entity. The sources are clock, UI, self, routine, external, answer and source.
- **FR-014**: One policy MUST decide each trigger. Equal triggers from different sources MUST get equal decisions, except where FR-024 and FR-025 name the source.
- **FR-015**: Each decision MUST add one record with the trigger and the outcome. A refusal MUST name its reason in the same words for each caller.
- **FR-016**: The run lifecycle of each routine MUST have three states: idle, running, and running with one run queued. A trigger during a run MUST queue one run, and more triggers MUST merge into it.
- **FR-017**: If the routine is idle, a hand-off, an answer, a UI press and an external request MUST start their work within 5 seconds.
- **FR-018**: Clock slots MUST still start runs, through the same entrance.

#### Sources

- **FR-019**: A source plugin MUST be able to create and update actionables of the kinds that it declares. It MUST NOT make a transition.
- **FR-020**: The host MUST poll all sources at most once a minute, with one shared agent call on a small model in total.
- **FR-021**: Each source MUST keep a cursor. The cursor MUST move only after the host stores the items of that poll.
- **FR-022**: Each item MUST carry a dedupe key. The store MUST hold at most one actionable for each source and key.
- **FR-023**: A new actionable MUST get the routine that handles its kind and state `new` as owner, and MUST start that routine through the entrance.

#### Risk and permissions

- **FR-024**: A `read` or `reversible` transition MUST apply without a question. An `outward` or `destructive` transition MUST ask you in the routine thread, unless the allow list of that routine holds it.
- **FR-025**: A transition with `confirm: true` MUST start only from a press in the app. The host MUST refuse it from a script or a thread agent.
- **FR-026**: Only you MUST be able to change an allow list, in the app. No node, routine, memory entry or external request MUST be able to change it.
- **FR-027**: An external request MUST start only a transition or a plugin action that `permissions.external` lists, and only for an actionable that its routine owns.

#### Routine threads

- **FR-028**: The thread panel MUST show a Routines group with one thread for each routine.
- **FR-029**: A node MUST be able to return a question. The host MUST then move the actionable to `waiting-on-you` and post the question in the routine thread, with the title of the actionable.
- **FR-030**: The host MUST store the agent session id with the step that asked. Your answer MUST continue that session.
- **FR-031**: The host MUST refuse an answer to an actionable that is no longer in `waiting-on-you`, and say so in the thread.
- **FR-032**: The routine threads MUST replace the Inbox. The Routines group MUST show the count of open questions of each routine. A notification MUST open its question in the routine thread.

#### Memory

- **FR-033**: After each step, a memory node on a small model MUST write zero or more entries. Each entry MUST have a type (answer, outcome, fact or preference), text, tags and a link to its step.
- **FR-034**: Nodes MUST get a tool that searches memory and returns the closest entries. The tool MUST NOT write, edit or delete.
- **FR-035**: You MUST be able to read, edit and delete each entry in the app.
- **FR-036**: A memory entry MUST NOT grant a permission, change an allow list or change a manifest.
- **FR-037**: The memory node MUST treat the text of the step as data. It MUST get no tool that writes outside memory.

### Key Entities

- **Actionable**: one item of work. It has an id, a kind, a source and a dedupe key, an owner, a state, a title, typed data, links and steps.
- **Step**: one state change. It has the transition, the trigger, the actor, the time and the outcome. A question step adds the agent session id, and a hand-off adds the old owner and the old kind.
- **Trigger**: one request. It has the routine, the source of the request, the kind of work, and the optional actionable and text.
- **Transition declaration**: a line of a routine manifest. It has an id, a label, its start states, its risk level, and optionally `input` and `confirm`.
- **Source cursor**: how far a source read, for each source.
- **Allow list**: the `outward` and `destructive` transitions that you allow, for each routine.
- **Memory entry**: a type, text, tags, a link to its step, and the time that it was written or edited.
- **Routine thread**: a thread for one routine, with its open and answered questions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a hand-off, an answer or a press, the next run starts within 5 seconds in 95 of 100 test runs.
- **SC-002**: A new outside item becomes an actionable, and its routine starts, within 90 seconds in 95 of 100 test runs.
- **SC-003**: With any number of sources, the app makes at most 1,440 poll agent calls a day.
- **SC-004**: In the tests, no `outward` or `destructive` transition applies without an entry in the allow list, whatever memory holds.
- **SC-005**: In the tests, equal triggers from a UI press, a script and a thread agent get equal decisions and equal refusal text.
- **SC-006**: After you answer a question in a routine thread, the routine does not ask it again for the same kind and subject. This holds in 9 of 10 test cases.
- **SC-007**: Triage and Factory run on actionables with no routine-specific code in the host, and `HostIsGenericTests` passes.

## Assumptions

- The Claude connectors are the only way to reach Slack, Gmail and Linear. Your company does not allow webhooks, so the app polls.
- The cost of one poll call a minute on a small model is accepted.
- The agent CLI can continue a session by its id. When it cannot, FR-030 falls back to a new session with the step history.
- One owner at a time is enough for the current routines. Parallel work on one actionable is out of scope.
- Memory is local to this Mac. Sync between Macs is out of scope.
- The memory search ranks by text match and tags first. A better ranking can come later.
- The board columns of today map to states: `planned` to `ready`, `working` to `working`, `needs-you` to `waiting-on-you`, `done` to `done` and `failed` to `failed`.
- This feature changes R6 of the constitution, because the host now owns the actionables, and the routine threads replace the Inbox. The plan amends the constitution to version 4.0.0.
