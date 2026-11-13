# Contract: The entrance, the policy and the routine threads

Each request to start work reaches `PluginHost.submit(_ trigger: Trigger)`. The fields of a trigger and of a decision are in [data-model.md](../data-model.md).

## Callers

| Caller | Source | Work |
| --- | --- | --- |
| A clock slot of the manifest | `clock` | `run` |
| A press in a plugin UI | `ui` | `transition`, or a plugin action |
| `routines.runSoon(delayMs)` | `self` | `run`, after the delay |
| `routines.actionables.request` | `self` | `transition` |
| `routines.actionables.handoff` | `routine` | `run` for the new owner |
| Your answer in a routine thread | `answer` | `transition` |
| `Routines --perform` from a script or a thread agent | `external` | `transition`, or a plugin action |
| A new actionable from a poll | `source` | `run` for the owner |

## The order of the checks

`Policy.decide` checks a trigger in this order and returns the first refusal.

1. The routine exists, and it has no blocker.
2. For `transition`: the actionable exists, and the routine owns it.
3. For the source `answer`: the actionable is in `waiting-on-you`, and its last step is the question that the trigger answers. This check comes before the state check, so a late answer gets `notWaiting` and not `wrongState`.
4. The manifest declares the transition, and it starts from the current state. For an Allow on a permission question, the policy uses the state before the `asked` step.
5. A transition with `input` has text that is not blank. For an Allow, the text of the request that waits counts.
6. A transition with `confirm: true` comes from the source `ui`. This check comes before the next one, so a script learns that only a press starts it.
7. For the source `external`: `permissions.external` lists the transition.
8. Risk: a `read` or `reversible` transition goes on. An `outward` or `destructive` one goes on for the sources `ui` and `answer` and for a transition in the allow list. The policy returns `ask` for each other case.
9. For `run`: the lifecycle state gives `startRun`, `queueRun` or `merge`. For `transition`: `callTransition`.

The world of the policy has no memory. Each source gets the same check and the same text, except in steps 3, 6, 7 and 8.

A plugin action is a trigger with the work `action` and no actionable. It gets checks 1, 5, 6 and 7, and the policy returns `callAction`.

## Refusal texts

| Refusal | Text |
| --- | --- |
| `noRoutine` | `the routine <id> does not exist` |
| `blocked` | the blocker, for example `the plugin is off` |
| `noActionable` | `there is no actionable <id>` |
| `notOwner` | `<routine> does not own actionable <id>` |
| `noTransition` | `<routine> has no transition <transition>` |
| `wrongState` | `<transition> does not start from <state>` |
| `needsText` | `the transition <label> needs text` |
| `notExternal` | `<routine> does not allow <transition> from outside the app` |
| `needsPress` | `<label> starts only from a press in the app` |
| `notWaiting` | `actionable <id> no longer waits on you` |
| `staleQuestion` | `this question was already answered` |
| `noAction` | `<routine> has no action <action>` |
| `needsItem` | `<action> needs an item` |
| `needsRequest` | `<transition> is <risk>, so it needs actionables.request` |
| `sourceCannotMove` | `a source cannot move an actionable` |
| `noHandler` | `no routine handles <kind> in <state>` |
| `sameRoutine` | `<routine> cannot hand an actionable to itself` |
| `badData` | the first fault of the data, for example `data.repo must be a string` |
| `badQuestion` | the fault of the question, for example `the question text has 1 to 2,000 characters` |

## Permission questions

After `ask`, the host adds an `asked` step and moves the actionable to `waiting-on-you`. The routine thread shows `<routine> wants to <label>: <title>` with three buttons.

| Button | Trigger |
| --- | --- |
| Allow once | The same transition, with the source `answer` and `grant: once`. |
| Always allow | The app adds the transition to the allow list, then the same as Allow once. |
| Deny | A `denied` step back to the state before the `asked` step. No handler runs. |

## Routine threads

The thread panel shows a Routines group above the threads of the agent. It has one row per loaded routine with its count of open questions. An actionable with no owner adds a No owner row. A routine thread lists the open questions first, each with the title of its actionable and a reply field or the permission buttons. Then it lists the answered questions, newest first.

A reply goes to one question. The app submits a trigger with the source `answer`, the transition of the question, your text and the id of the question step. Before the handler runs, the host adds an `answered` step with your text. A refusal shows under the question.

A question posts a notification with the routine id and the step id. A click opens the thread panel at that question. The sidebar shows the count of open questions of each routine. The Inbox is gone.

## External requests

```text
Routines --perform <routine> <transition-or-action> [--item <id>] [text]
routines://perform?plugin=<routine>&action=<id>&item=<id>&text=<text>&reply=<file>
```

With `--item`, the request is a transition trigger with the source `external`. Without it, it is a plugin action, as today. The answer is the status of the move, or `Error: <refusal text>`.

## The `<routine-items>` block

Each `<item>` of a thread turn adds three lines: the kind, the state, and the transitions that a script can perform now.

```text
Kind: bug
State: waiting-on-you
External transitions now: answer, drop
```
