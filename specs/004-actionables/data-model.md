# Data Model: Actionables

The host owns each entity on this page. The plugin contract is in [contracts/actionables.md](contracts/actionables.md). The reasons for each choice are in [research.md](research.md).

## Files

| Path in the data folder | What it holds | Who writes it |
| --- | --- | --- |
| `actionables/<id>.json` | One actionable with its steps | The host |
| `actionables/next-id.json` | The next id | The host |
| `sources/<plugin>.json` | The cursor and the last error of one source | The host |
| `decisions/<yyyy-mm-dd>.jsonl` | One line per decision, 14 days | The host |
| `runs/polls/<yyyy-mm-dd>.log` | The log of each poll, 14 days | The host |
| `memory/entries.json` | The memory entries | The host, and you in the app |
| `memory/pending.json` | The steps that wait for the memory node | The host |
| `board/<plugin>.json.migrated` | The old cards, after the move | Nobody |
| Keychain item `Routines allow list` | The allow list | You, in the app |

A plugin can read these files, but `PermissionCheck` refuses each write of a plugin to them.

## State

The place of an actionable in the shared lifecycle.

| Value | Meaning | Closed |
| --- | --- | --- |
| `new` | A source or a hand-off just created it. No work started. | No |
| `ready` | The owner can start work. | No |
| `working` | The owner works on it now. | No |
| `waiting-on-you` | It has an open question to you. | No |
| `waiting-on-others` | It waits on a person or a system outside the app. | No |
| `done` | The work is complete. | Yes |
| `failed` | The work stopped with an error. | Yes |
| `dropped` | Nobody does the work. | Yes |

The retention of the owner deletes a closed actionable after its last change, as with done cards today.

The board adapter maps the columns of today: `planned` to `ready`, `working` to `working`, `needs-you` to `waiting-on-you`, `done` to `done` and `failed` to `failed`. Back to a column, `new` maps to `planned`, `waiting-on-others` to `working`, and `dropped` to `done`.

## Actionable

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | A whole number from `next-id.json`. It never changes. |
| `kind` | string | Lowercase letters, digits and `-`. |
| `source` | string | The id of the plugin that created it. |
| `dedupeKey` | string | Unique for each `source`. |
| `owner` | string or null | A loaded routine, or null. Null means that no routine handles it, or that its routine is gone. |
| `pastOwners` | [string] | Each earlier owner, oldest first. |
| `state` | State | One value of the lifecycle. |
| `title` | string | 1 to 200 characters. |
| `body` | string? | Markdown for the UI. |
| `status` | string? | One line, for example "Working on it…". |
| `tags` | [string]? | |
| `links` | [Link] | `{ label, url }`, `http` or `https` only. |
| `images` | [string]? | Absolute paths that the plugin wrote. |
| `date`, `progress` | string?, number? | As on a card today. |
| `data` | object | At most 32 KB as JSON. If a plugin declares the schema of `kind`, the data fits it. |
| `steps` | [Step] | Oldest first. The host only appends. |
| `createdAt`, `updatedAt` | time | Set by the host. |

`body`, `status`, `tags`, `images`, `date` and `progress` are display fields. The UI controls of today draw them, and the host does not read them.

## Step

One change of an actionable. A state change adds exactly one step (FR-003).

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | `<actionable id>.<number>`, from 1. |
| `at` | time | |
| `action` | Action | See the table below. |
| `actor` | string | A routine id, a source id, `you` or `host`. |
| `trigger` | string | The id of the decision that started the call. |
| `from`, `to` | State | Equal for a step without a state change. |
| `outcome` | string? | The status line that the move returned. |
| `question` | Question? | Only with `to` = `waiting-on-you`. |
| `answer` | string? | Your text, on an `answered` step. |
| `oldOwner`, `oldKind` | string? | Only on a `handoff` step. |

| Action | Who makes it | What it does |
| --- | --- | --- |
| `transition:<id>` | The owner | A declared transition, from a move or a handler. |
| `handoff` | The old owner | Changes the owner, and can change the kind, the data and the state. |
| `created` | A source | The first step. |
| `updated` | A source | Changes the data. The state stays. |
| `asked` | The host | A permission question. The state becomes `waiting-on-you`. |
| `answered` | You | Records your answer before the handler runs. The state stays for a question. For a permission question, it moves back to the state before the `asked` step. |
| `denied` | You | Moves back to the state before the `asked` step. |
| `board` | A plugin of today | A change through the board adapter. |
| `migrated` | The host | The first step of a migrated card. |

## Question

| Field | Type | Rule |
| --- | --- | --- |
| `text` | string | 1 to 2,000 characters. |
| `transition` | string? | The transition that your answer starts. It starts from `waiting-on-you` and has `input`. |
| `session` | Session? | `{ id, cwd }` of the agent session that asked. |
| `permission` | string? | Set on an `asked` step: the transition that waits for Allow. |
| `input` | string? | Set on an `asked` step: the text of the request that waits, so Allow passes it to the handler. |

A question has `transition` or `permission`, never both.

## Manifest additions

| Field | Type | Who has it |
| --- | --- | --- |
| `handles` | [{ kind, states }] | A routine plugin |
| `transitions` | [Transition declaration] | A routine plugin |
| `kinds` | [string] | Any plugin. Each kind needs an entry in `dist/kinds.json`. |
| `source` | { kinds, tools } | A source plugin |

A manifest with both `source` and `handles` or `transitions` does not load. A manifest with none of them is a plugin of today and uses the board adapter.

### Transition declaration

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | Unique in the manifest. |
| `label` | string | The text of its button and of its question. |
| `from` | [State] | At least one state. |
| `risk` | `read`, `reversible`, `outward` or `destructive` | Required. |
| `input` | { placeholder }? | The trigger needs text that is not blank. |
| `confirm` | bool? | Only a press in the app starts it, after the dialog. |
| `style` | `primary`, `destructive` or `normal`? | As for an action. |

### Handles table

`Handles.build(manifests)` maps each pair of kind and state to one routine. It returns the plugins that it refused, with the conflict as the problem of the plugin (FR-009). The catalog order decides which plugin loads first.

## Trigger

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | A UUID. |
| `routine` | string | The routine that the trigger asks to work. |
| `source` | `clock`, `ui`, `self`, `routine`, `external`, `answer` or `source` | Who asked. |
| `work` | `run`, `transition` or `action` | `action` is a plugin action of the manifest, with no actionable. |
| `actionable` | string? | Required for `transition`. |
| `transition` | string? | Required for `transition`. For `action`, the id of the plugin action. |
| `text` | string? | |
| `answers` | string? | The id of the question step, for the source `answer`. |
| `grant` | `once` or `always`? | Allow on a permission question. |
| `at` | time | |

## Decision

`Policy.decide(trigger, world)` returns one value.

| Case | Effect |
| --- | --- |
| `startRun` | The run lifecycle is idle. The host starts a run now. |
| `queueRun` | A run is in progress. One more run follows it. |
| `merge` | A run is already queued. The trigger joins it. |
| `callTransition` | The host queues `onTransition` for the actionable, or `onAction` for a plugin of today. |
| `callAction` | The host queues `onPluginAction`. |
| `ask(transition)` | The host adds an `asked` step and posts the permission question. |
| `refuse(Refusal)` | Nothing runs. The record names the reason. |

`world` holds the manifests, the handles table, the blocker of each routine, the stored actionable, the allow list of the routine and its lifecycle state. It holds no memory. The texts of each `Refusal` are in [contracts/entrance.md](contracts/entrance.md).

A decision record is one JSON line: `{ id, at, trigger, decision, reason? }`. The `id` of the record is the `trigger` of each step that the call makes.

## Run lifecycle

```text
idle    --run trigger-->  running   (start a run)
running --run trigger-->  queued
queued  --run trigger-->  queued    (merge)
running --run ended-->    idle
queued  --run ended-->    running   (start the queued run)
```

Transition triggers do not change it. They wait in the serial queue of the plugin.

## Source cursor

| Field | Type | Rule |
| --- | --- | --- |
| `cursor` | JSON value | Opaque to the host. Null before the first poll. |
| `polledAt` | time? | The last good poll. |
| `error` | string? | The last failure. A good poll clears it. |

## Allow list

A map from a routine id to a set of transition ids. The app reads it from the Keychain at launch and writes it after each change in the Settings tab or after Always allow. The manifest must declare each kept id as `outward` or `destructive`. The host drops the other ids.

## Memory entry

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | A UUID. |
| `type` | `answer`, `outcome`, `fact` or `preference` | |
| `text` | string | 1 to 1,000 characters. |
| `tags` | [string] | At most 8, lowercase. |
| `routine` | string | The owner at the time of the step. |
| `step` | string | The id of the step. |
| `writtenAt`, `editedAt` | time, time? | |

An entry has no field that the policy reads. You can edit `text` and `tags`, and delete the entry.

## Routine thread

Derived, not stored. `RoutineThread.build(routine, actionables)` returns:

| Field | Meaning |
| --- | --- |
| `routine` | The routine id, or null for No owner. |
| `open` | Each actionable in `waiting-on-you` whose last step asks, with its title and the question. |
| `answered` | Each question step with the `answered` or `denied` step after it, newest first. |
| `count` | The number of open questions. |
