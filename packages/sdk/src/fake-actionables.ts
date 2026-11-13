// The actionable store of the test host. It has the owner and transition checks of the host, so plugin tests can move actionables.
import type { Handoff, Move, RoutinesHost, State, Step, StoredActionable, TransitionDeclaration } from "./host.ts";
import { err, ok, type Result } from "./result.ts";

export type FakeActionables = {
  api: RoutinesHost["actionables"];
  store: Map<string, StoredActionable>;
  // Each `request` call, in order.
  requests: { id: string; transition: string; text?: string }[];
  // Adds an actionable that the routine owns, in `ready` unless the seed says otherwise.
  add: (seed: Partial<StoredActionable> & { kind: string; title: string }) => StoredActionable;
};

const SAFE_RISKS = new Set(["read", "reversible"]);

type Checked = { actionable: StoredActionable; transition: TransitionDeclaration };

export const fakeActionables = (routine: () => string, transitions: () => TransitionDeclaration[]): FakeActionables => {
  const store = new Map<string, StoredActionable>();
  const requests: FakeActionables["requests"] = [];
  let nextId = 1;
  const now = () => new Date().toISOString();

  const owned = (id: string): Result<StoredActionable> => {
    const actionable = store.get(id);
    if (!actionable) return err(`there is no actionable ${id}`);
    return actionable.owner === routine() ? ok(actionable) : err(`${routine()} does not own actionable ${id}`);
  };

  const declared = (id: string, transitionId: string): Result<Checked> => {
    const actionable = owned(id);
    if (!actionable.ok) return actionable;
    const transition = transitions().find((entry) => entry.id === transitionId);
    if (!transition) return err(`${routine()} has no transition ${transitionId}`);
    if (!transition.from.includes(actionable.value.state)) return err(`${transitionId} does not start from ${actionable.value.state}`);
    return ok({ actionable: actionable.value, transition });
  };

  const append = (actionable: StoredActionable, step: Omit<Step, "id" | "at" | "actor" | "trigger">, changes: Partial<StoredActionable>) => {
    const at = now();
    const next: StoredActionable = {
      ...actionable,
      ...changes,
      steps: [...actionable.steps, { ...step, id: `${actionable.id}.${actionable.steps.length + 1}`, at, actor: routine(), trigger: "test" }],
      updatedAt: at,
    };
    store.set(next.id, next);
    return next;
  };

  const move = async (id: string, { transition, ...change }: Move & { transition: string }): Promise<Result<StoredActionable>> => {
    const checked = declared(id, transition);
    if (!checked.ok) return checked;
    const { actionable, transition: declaration } = checked.value;
    if (!SAFE_RISKS.has(declaration.risk)) return err(`${transition} is ${declaration.risk}, so it needs actionables.request`);
    const { to, question, ...fields } = change;
    const state: State = question ? "waiting-on-you" : to;
    const step = { action: `transition:${transition}`, from: actionable.state, to: state, ...(fields.status ? { outcome: fields.status } : {}), ...(question ? { question } : {}) };
    return ok(shown(append(actionable, step, { ...fields, state })));
  };

  const request = async (id: string, transition: string, text?: string): Promise<Result<"queued" | "asked">> => {
    const checked = declared(id, transition);
    if (!checked.ok) return checked;
    requests.push({ id, transition, ...(text === undefined ? {} : { text }) });
    return ok(SAFE_RISKS.has(checked.value.transition.risk) ? "queued" : "asked");
  };

  // The test host does not know the other routines, so the new owner is null.
  const handoff = async (id: string, { state, kind, title, data }: Handoff): Promise<Result<StoredActionable>> => {
    const actionable = owned(id);
    if (!actionable.ok) return actionable;
    const old = actionable.value;
    const step = { action: "handoff", from: old.state, to: state, oldOwner: routine(), oldKind: old.kind };
    const changes = { state, owner: null, pastOwners: [...old.pastOwners, routine()], kind: kind ?? old.kind, title: title ?? old.title, data: data ?? old.data };
    return ok(shown(append(old, step, changes)));
  };

  const add: FakeActionables["add"] = (seed) => {
    const at = now();
    const id = String(nextId++);
    const actionable: StoredActionable = {
      id,
      source: routine(),
      dedupeKey: `test-${id}`,
      owner: routine(),
      pastOwners: [],
      state: "ready",
      links: [],
      data: {},
      steps: [],
      createdAt: at,
      updatedAt: at,
      readOnly: false,
      ...seed,
    };
    store.set(actionable.id, actionable);
    return actionable;
  };

  const visible = (actionable: StoredActionable, past: boolean) => actionable.owner === routine() || (past && actionable.pastOwners.includes(routine()));

  const shown = (actionable: StoredActionable): StoredActionable => ({ ...actionable, readOnly: actionable.owner !== routine() });

  const api: RoutinesHost["actionables"] = {
    list: async ({ states, past = false } = {}) =>
      ok([...store.values()].filter((actionable) => visible(actionable, past) && (!states || states.includes(actionable.state))).map(shown)),
    get: async (id) => {
      const actionable = store.get(id);
      return ok(actionable && visible(actionable, true) ? shown(actionable) : null);
    },
    move,
    request,
    handoff,
  };

  return { api, store, requests, add };
};
