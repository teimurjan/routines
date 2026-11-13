# Contract: Actionables for routine plugins

This contract adds to `specs/001-swift-host/contracts/plugin-api.md` and `specs/003-custom-ui-everywhere/contracts/actions.md`. The fields are in [data-model.md](../data-model.md). Each host call returns `{ ok: true, value }` or `{ ok: false, error }` (R4).

## Manifest

```json
{
  "id": "factory",
  "handles": [{ "kind": "bug", "states": ["new", "ready"] }],
  "kinds": ["bug"],
  "transitions": [
    { "id": "start", "label": "Start", "from": ["new", "ready"], "risk": "reversible" },
    { "id": "answer", "label": "Answer", "from": ["waiting-on-you"], "risk": "reversible", "input": { "placeholder": "Your answer" } },
    { "id": "open-pr", "label": "Open PR", "from": ["working"], "risk": "outward" },
    { "id": "approve", "label": "Approve", "from": ["waiting-on-you"], "risk": "outward", "confirm": true, "style": "primary" },
    { "id": "drop", "label": "Drop", "from": ["new", "ready", "waiting-on-you"], "risk": "reversible" }
  ],
  "permissions": { "external": ["answer", "drop"] }
}
```

The host refuses to load a manifest in these cases, and the reason becomes the problem of the plugin:

1. Another loaded routine handles the same kind and state (FR-009).
2. A name in `kinds` has no schema in `dist/kinds.json`, or another loaded plugin declares the same kind.
3. A transition has no `risk`, an empty `from`, or a state outside the lifecycle.
4. Two transitions, or a transition and an action, have the same id.
5. The manifest has `source` and also `handles` or `transitions`.

`permissions.external` can list transition ids and plugin action ids.

## `dist/kinds.json`

```json
{ "bug": { "type": "object", "required": ["repo", "details"], "properties": { "repo": { "type": "string" }, "details": { "type": "string", "maxLength": 8000 } }, "additionalProperties": false } }
```

The workspace build writes it from the Zod schemas that `src/kinds.ts` exports by kind name. The host reads `type`, `properties`, `required`, `items`, `enum`, `additionalProperties` and `maxLength`, and it refuses a schema with another keyword.

## Plugin functions

```ts
type RunContext = {
  settings: Record<string, string>;
  // The string of today stays: clock is "schedule", self is "soon", ui is "action", and each other source keeps its name.
  trigger: string;
  source: TriggerSource;
  actionable?: string;
};

type TransitionEvent = {
  actionable: StoredActionable;
  transition: string;
  text?: string;
  // Set when the trigger answers a question that carried a session.
  session?: { id: string; cwd: string };
  // The steps since the last answer, for a session that cannot resume.
  history: Step[];
};

type Move = {
  to: State;
  status?: string;
  title?: string;
  body?: string;
  data?: Record<string, unknown>;
  links?: { label: string; url: string }[];
  question?: { text: string; transition: string; session?: { id: string; cwd: string } };
};

definePlugin({
  run?: (context: RunContext) => Promise<Result<unknown> | void>,
  onTransition?: (event: TransitionEvent, context: RunContext) => Promise<Result<Move>>,
  onPluginAction?: (event: PluginActionEvent, context: RunContext) => Promise<Result<string>>,
});
```

The host calls `onTransition` only after the policy allows the trigger. It applies the returned move as one step with the action `transition:<id>`. New data in the move must fit the kind. With a question, `to` must be `waiting-on-you`. A failure adds no step. The host sets `status` to `Error: <reason>` and records the failure in the run log.

## Host calls

```ts
routines.actionables.list(options?: { states?: State[]; past?: boolean }): Promise<Result<StoredActionable[]>>;
routines.actionables.get(id: string): Promise<Result<StoredActionable | null>>;
routines.actionables.move(id: string, move: Move & { transition: string }): Promise<Result<StoredActionable>>;
routines.actionables.request(id: string, transition: string, text?: string): Promise<Result<"queued" | "asked">>;
routines.actionables.handoff(id: string, change: { state: State; kind?: string; title?: string; data?: Record<string, unknown> }): Promise<Result<StoredActionable>>;
```

| Call | The host checks | Then |
| --- | --- | --- |
| `list` | Nothing. | The owned actionables. With `past`, also those that the routine owned before, with `readOnly: true`. |
| `get` | The routine owns it or owned it. | The actionable, or null. |
| `move` | The owner, the declared transition, the start state, the end state, a risk of `read` or `reversible`, and new data against the kind. | One step. |
| `request` | The same as a trigger with the source `self`. | `queued` for an allowed trigger. `asked` for a permission question. |
| `handoff` | The owner, one handler for the new kind and state, not the same routine, the data against the new kind. | One `handoff` step, and a run trigger with the source `routine` for the new owner. |

A source plugin gets the error `a source cannot move an actionable` for `move`, `request` and `handoff`.

## Agent sessions and memory

```ts
runNode<Output>(task: AgentTask<Output> & { session?: { resume?: { id: string; cwd: string } }; memory?: boolean }):
  Promise<Result<{ output: z.infer<Output>; session: { id: string; cwd: string } }>>;
```

`runNode` passes `--session-id <new UUID>`, or `--resume <id>` with the stored `cwd`. With `memory: true`, it adds the memory server of [memory.md](memory.md) and its tool. If the resume fails, `runNode` starts a new session once. It then logs `the session <id> did not resume, so a new session started`. `runAgent` stays for nodes that need neither.

`asks(schema)` from `@routines/sdk` returns `{ question: string, result?: schema }`, so a node can return a question instead of its result. `answerOf(output)` gives the question when it is not blank, else the result. The schema is an object and not a union, because the API refuses an output schema without `type: object` at its root.

## Plugin UI

The snapshot adds two fields. `items` stays for the UIs of today and holds the owned actionables in the card shape.

```ts
type Snapshot = {
  actionables: (StoredActionable & { readOnly: boolean; allowed: string[] })[];
  transitions: TransitionDeclaration[];
  // The fields of today follow.
};
```

`allowed` lists the transitions that start from the current state. The page message `{ type: "transition", actionable, transition, text? }` becomes a trigger with the source `ui`. For `confirm: true`, the host dialog asks first, as for an action. `@routines/ui` adds `TransitionButton`, which reads the declaration and calls this message.

## The board adapter

A plugin with no `handles`, `transitions` or `source` keeps `board.upsert`, `board.remove`, `board.list` and `onAction`. Its cards are actionables with the plugin as source, owner and kind, and the card id as dedupe key. A changed column adds a `board` step. `board.remove` moves the actionable to `dropped`. Its item actions count as `outward` transitions from each open state.
