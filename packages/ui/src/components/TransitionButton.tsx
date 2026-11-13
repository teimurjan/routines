import type { Result } from "@routines/sdk";
import { actionableOf, transitionOf } from "../bridge.ts";
import { usePlugin } from "../context.tsx";
import { Press } from "./Press.tsx";

type Props = {
  actionableId: string;
  transitionId: string;
  shortcut?: string;
  onResult?: (result: Result<string | null>) => void;
};

// A transition of the manifest as a button. It shows only while the transition starts from the state of the actionable.
export const TransitionButton = ({ actionableId, transitionId, shortcut, onResult }: Props) => {
  const plugin = usePlugin();
  const transition = transitionOf(plugin.snapshot, transitionId);
  const actionable = actionableOf(plugin.snapshot, actionableId);
  if (!transition || !actionable || actionable.readOnly || !actionable.allowed.includes(transitionId)) return null;
  const run = (text: string | undefined) => plugin.transition(actionableId, transitionId, text);
  return (
    <Press label={transition.label} style={transition.style} input={transition.input} busy={plugin.isPending(actionableId)} shortcut={shortcut} run={run} onResult={onResult} />
  );
};
