# Quickstart: Validate actionables

These steps prove each user story. The contracts are in [contracts/](contracts/), and the fields are in [data-model.md](data-model.md).

## Prerequisites

- macOS 15 or later, Xcode with Swift 6, and Bun 1.3.
- The `claude` CLI 2.1.323 or later, logged in, for the checks on a real agent.
- For story 4 on a real agent: the Slack connector of claude.ai.

## 1. Run all checks

From the repo root, run the full check. It runs the type check, the plugin tests, the plugin build and the host tests.

```sh
bun run check
```

Expected: each step passes. `HostIsGenericTests` passes with the new folders (SC-007, FR-011).

## 2. Check the rules one story at a time

Run the host tests of each story from `app/`.

```sh
cd app
swift test --filter 'ActionableStoreTests|KindSchemaTests|HandlesTests|MigrationTests'   # Story 1
swift test --filter 'PolicyTests|RunLifecycleTests|EntranceTimingTests'                 # Story 2
swift test --filter 'RoutineThreadTests'                                                # Story 3
swift test --filter 'PollPlanTests'                                                     # Story 4
swift test --filter 'RiskTests'                                                         # Story 5
swift test --filter 'MemoryTests'                                                       # Story 6
swift test --filter 'ExternalActionTests|ThreadContextTests'                            # Story 7
```

Expected outcomes:

| Story | The tests show |
| --- | --- |
| 1 | One step per move. Refusals for another owner, an unlisted transition, a wrong state and data that does not fit. A hand-off changes the owner in one step. The snapshot holds only owned and past actionables. |
| 2 | With a fake clock, a hand-off, an answer and a press start a run within 5 seconds. Three triggers during a run give one more run. Equal triggers from `ui`, `external` and `self` give equal refusal text. |
| 3 | A question moves the actionable to `waiting-on-you` with the session in the step. An answer after a reload of the store gets the same session. A stale answer gets `actionable <id> no longer waits on you`. |
| 4 | Three sources make one agent call. Two new items and one known item add two actionables and one `updated` step. A failed poll keeps each cursor. |
| 5 | Each risk level with an empty and a full allow list. A memory entry with "always allow merges" changes no decision. `confirm: true` from `external` gets `<label> starts only from a press in the app`. |
| 6 | The search finds an answer by its words and tags. The server answers `tools/list` with one tool and refuses each other method. A failed memory call keeps its steps in the queue. |
| 7 | `--perform` with `--item` applies a listed transition and refuses an unlisted one. The `<routine-items>` block lists the external transitions of each item now. |

## 3. Check a resume with a JSON Schema on the real CLI

This proves research section 11. Run it in an empty folder.

```sh
mkdir -p /tmp/resume-check && cd /tmp/resume-check
id=$(uuidgen | tr 'A-Z' 'a-z')
schema='{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}'
echo 'Ask me one short question about a color.' | claude -p --restricted --session-id "$id" --output-format json --json-schema "$schema"
echo 'Green. Now repeat your question word for word.' | claude -p --restricted --resume "$id" --output-format json --json-schema "$schema"
```

Expected: the second `structured_output.text` repeats the question of the first call.

## 4. Check the app by hand

Build and open the app. Keep two fixture routines in `workspace/plugins`: one that hands a `bug` to the other, and one whose node asks a question.

1. Press a transition button in the UI of the first routine. Expected: within 5 seconds, the Runs tab of the second routine shows a run with the trigger `routine`.
2. Open the thread panel. Expected: a Routines group with one row per routine, and a count on the row of the second routine.
3. Answer the question in its routine thread. Expected: within 5 seconds, the run log shows `--resume` with the session id of the question step, and the actionable leaves `waiting-on-you`.
4. Quit and open the app while a question is open, then answer it. Expected: the same session id in the run log.
5. Run `Routines --perform <routine> <transition> --item <id> "text"` from Terminal. Expected: the answer of the move, or the refusal text of [entrance.md](contracts/entrance.md).
6. Open Settings of a routine with an `outward` transition. Turn its switch on. Expected: the next request of that transition applies with no question.
7. Open Memory. Edit an entry, then make a node search for it. Expected: the node gets your text.
8. Check that the sidebar has no Inbox, and that a click on a question notification opens the routine thread.

## 5. Check the poll budget

Turn on a source plugin and leave the app open for 10 minutes.

```sh
grep -c 'poll started' ~/Library/Application\ Support/Routines/runs/polls/$(date +%F).log
```

Expected: at most one poll per minute, so at most 10 lines for 10 minutes (SC-003). A Slack mention that you post shows as an actionable within 90 seconds (SC-002).

## 6. Check memory on a real agent (SC-006)

Run the memory eval of the fixture routine 10 times. Each case asks a question, answers it, and gives a second actionable of the same kind and subject.

```sh
ROUTINES_AGENT_EVALS=1 swift test --filter MemoryEvalTests
```

Expected: in at least 9 of 10 cases, the second node finds the answer with its search and does not ask again.
