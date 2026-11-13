import type { Result } from "@routines/sdk";
import { actionOf } from "../bridge.ts";
import { usePlugin } from "../context.tsx";
import { Press } from "./Press.tsx";

type Props = {
  actionId: string;
  // With an item, the button runs an item action of the manifest. Without one, a plugin action.
  cardId?: string;
  shortcut?: string;
  onResult?: (result: Result<string | null>) => void;
};

// A manifest action as a button, or as a field and a button when the action needs text.
export const ActionButton = ({ actionId, cardId, shortcut, onResult }: Props) => {
  const plugin = usePlugin();
  const action = actionOf(plugin.snapshot, actionId);
  if (!action || (action.target === "item") !== (cardId !== undefined)) return null;
  const run = (text: string | undefined) => (cardId === undefined ? plugin.performPluginAction(actionId, text) : plugin.perform(cardId, actionId, text));
  return <Press label={action.label} style={action.style} input={action.input} busy={plugin.isPending(cardId)} shortcut={shortcut} run={run} onResult={onResult} />;
};
