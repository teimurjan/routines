import type { Result } from "@routines/sdk";
import { useCallback, useEffect, useState } from "preact/hooks";
import { bridge, connect, onHostEvent, type Snapshot } from "./bridge.ts";

export type PluginState = {
  // Undefined until the first snapshot arrives.
  snapshot: Snapshot | undefined;
  error: string | undefined;
  perform: (cardId: string, actionId: string, text?: string) => Promise<Result<string | null>>;
  performPluginAction: (actionId: string, text?: string) => Promise<Result<string | null>>;
  transition: (actionableId: string, transitionId: string, text?: string) => Promise<Result<string | null>>;
  openLink: (url: string) => Promise<Result<null>>;
  // True while an action or a transition of the item runs, or while a menu action runs when no id is given.
  isPending: (cardId?: string) => boolean;
};

const MENU = "";

// The snapshot of the plugin and its actions. It also sets `--accent` on the root element from the appearance.
// Only `PluginProvider` calls it, so a page has one connection to the host.
export const usePluginState = (): PluginState => {
  const [snapshot, setSnapshot] = useState<Snapshot>();
  const [error, setError] = useState<string>();
  // The presses that wait for the host dialog or for the host to queue them, so a second press cannot start them twice.
  const [pressed, setPressed] = useState<ReadonlySet<string>>(new Set());

  useEffect(() => connect(setSnapshot, setError), []);

  const accent = snapshot?.appearance.accent;
  useEffect(() => {
    if (accent) document.documentElement.style.setProperty("--accent", accent);
  }, [accent]);

  const track = useCallback(async <T>(key: string, work: () => Promise<Result<T>>) => {
    setPressed((current) => new Set(current).add(key));
    const result = await work();
    setPressed((current) => new Set([...current].filter((entry) => entry !== key)));
    return result;
  }, []);

  const perform = useCallback(
    (cardId: string, actionId: string, text?: string) => track(cardId, () => bridge.perform(cardId, actionId, text)),
    [track],
  );
  const performPluginAction = useCallback((actionId: string, text?: string) => track(MENU, () => bridge.performPluginAction(actionId, text)), [track]);
  const transition = useCallback(
    (actionableId: string, transitionId: string, text?: string) => track(actionableId, () => bridge.transition(actionableId, transitionId, text)),
    [track],
  );

  const isPending = (cardId?: string) =>
    cardId === undefined ? pressed.has(MENU) || snapshot?.pending.plugin === true : pressed.has(cardId) || snapshot?.pending.items.includes(cardId) === true;

  return { snapshot, error, perform, performPluginAction, transition, openLink: bridge.openLink, isPending };
};

// Calls the handler when you open a notification of an item.
export const useFocus = (handler: (cardId: string) => void) => {
  useEffect(
    () =>
      onHostEvent((event) => {
        if (event.type === "focus") handler(event.value.cardId);
      }),
    [handler],
  );
};

// The id of the item that a notification or the Inbox asked for. `onFocus` can switch to the tab that holds it, and the page scrolls to it.
export const useFocusedItem = (onFocus?: (cardId: string) => void) => {
  const [focusedId, setFocusedId] = useState<string>();
  useFocus(
    useCallback(
      (cardId: string) => {
        onFocus?.(cardId);
        setFocusedId(cardId);
        // The item renders after the state change, so the scroll waits one frame.
        requestAnimationFrame(() => document.getElementById(cardId)?.scrollIntoView({ block: "center" }));
      },
      [onFocus],
    ),
  );
  return focusedId;
};
