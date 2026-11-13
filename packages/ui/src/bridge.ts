// A typed client of the plugin UI bridge. See specs/002-plugin-ui/contracts/plugin-ui.md.
import type { CardAction, Page, Result, StoredActionable, StoredCard, TransitionDeclaration } from "@routines/sdk";

// `allowed` lists the transitions that start from the current state.
export type SnapshotActionable = StoredActionable & { allowed: string[] };

export type Snapshot = {
  plugin: { id: string; name: string; emoji?: string; color: string };
  // Newest first.
  items: StoredCard[];
  page: Page | null;
  actions: CardAction[];
  pending: { items: string[]; plugin: boolean };
  status: string | null;
  appearance: { scheme: "light" | "dark"; accent: string };
  // The actionables that the routine owns, and those that it owned before with `readOnly: true`.
  actionables: SnapshotActionable[];
  transitions: TransitionDeclaration[];
};

export type HostEvent = { type: "snapshot"; value: Snapshot } | { type: "focus"; value: { cardId: string } };

type Message =
  | { type: "ready" }
  | { type: "snapshot" }
  | { type: "perform"; cardId: string; actionId: string; text?: string }
  | { type: "performPluginAction"; actionId: string; text?: string }
  | { type: "transition"; actionable: string; transition: string; text?: string }
  | { type: "openLink"; url: string };

type Handler = { postMessage: (message: Message) => Promise<unknown> };

declare global {
  interface Window {
    webkit?: { messageHandlers?: { routines?: Handler } };
  }
}

const err = (error: string): Result<never> => ({ ok: false, error });

const isResult = (value: unknown): value is Result<unknown> => typeof value === "object" && value !== null && typeof (value as { ok?: unknown }).ok === "boolean";

const send = async <T>(message: Message): Promise<Result<T>> => {
  const handler = window.webkit?.messageHandlers?.routines;
  if (!handler) return err("the page runs outside the Routines app");
  try {
    const reply = await handler.postMessage(message);
    return isResult(reply) ? (reply as Result<T>) : err("the host sent no result");
  } catch (cause) {
    return err(cause instanceof Error ? cause.message : String(cause));
  }
};

const withText = (text: string | undefined) => (text === undefined ? {} : { text });

// Each call resolves with a Result. An action with `confirm: true` resolves after the host dialog, with "Cancelled." if you cancel.
export const bridge = {
  ready: () => send<null>({ type: "ready" }),
  snapshot: () => send<Snapshot>({ type: "snapshot" }),
  perform: (cardId: string, actionId: string, text?: string) => send<string | null>({ type: "perform", cardId, actionId, ...withText(text) }),
  performPluginAction: (actionId: string, text?: string) => send<string | null>({ type: "performPluginAction", actionId, ...withText(text) }),
  // A transition with `confirm: true` resolves after the host dialog, as an action does.
  transition: (actionable: string, transition: string, text?: string) => send<string | null>({ type: "transition", actionable, transition, ...withText(text) }),
  openLink: (url: string) => send<null>({ type: "openLink", url }),
};

const isHostEvent = (value: unknown): value is HostEvent =>
  typeof value === "object" && value !== null && ["snapshot", "focus"].includes((value as { type?: unknown }).type as string);

// Calls the listener on each `routines` event of the host, and returns the function that stops it.
export const onHostEvent = (listener: (event: HostEvent) => void) => {
  const handle = (event: Event) => {
    const { detail } = event as CustomEvent<unknown>;
    if (isHostEvent(detail)) listener(detail);
  };
  window.addEventListener("routines", handle);
  return () => window.removeEventListener("routines", handle);
};

// Gets the first snapshot, follows each new one, and then tells the host that the page can show.
export const connect = (onSnapshot: (snapshot: Snapshot) => void, onError: (error: string) => void) => {
  const stop = onHostEvent((event) => {
    if (event.type === "snapshot") onSnapshot(event.value);
  });
  void (async () => {
    const first = await bridge.snapshot();
    if (first.ok) onSnapshot(first.value);
    else onError(first.error);
    await bridge.ready();
  })();
  return stop;
};

// The manifest action with this id, or undefined.
export const actionOf = (snapshot: Snapshot | undefined, actionId: string) => snapshot?.actions.find(({ id }) => id === actionId);

// The transition declaration with this id, or undefined.
export const transitionOf = (snapshot: Snapshot | undefined, transitionId: string) => snapshot?.transitions.find(({ id }) => id === transitionId);

// The actionable with this id, or undefined.
export const actionableOf = (snapshot: Snapshot | undefined, id: string) => snapshot?.actionables.find((actionable) => actionable.id === id);

// The URL of an image path that a card of the plugin lists in `images`.
export const imageUrl = (path: string) => `/_image/${encodeURIComponent(path)}`;
