import type { Result } from "@routines/sdk";
import { useState } from "preact/hooks";
import { actionOf } from "../bridge.ts";
import { usePlugin } from "../context.tsx";
import { Button } from "./Button.tsx";

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
  const [text, setText] = useState("");
  const [error, setError] = useState<string>();
  const action = actionOf(plugin.snapshot, actionId);
  if (!action || (action.target === "item") !== (cardId !== undefined)) return null;

  const busy = plugin.isPending(cardId);
  const blank = action.input !== undefined && text.trim() === "";
  const run = async () => {
    if (busy || blank) return;
    const input = action.input ? text : undefined;
    const result = cardId === undefined ? await plugin.performPluginAction(actionId, input) : await plugin.perform(cardId, actionId, input);
    // You pressed Cancel in the host dialog, so the page needs no message.
    setError(result.ok || result.error === "Cancelled." ? undefined : result.error);
    if (result.ok) setText("");
    onResult?.(result);
  };
  const button = (
    <Button variant={action.style ?? "normal"} disabled={busy || blank} shortcut={shortcut} onClick={() => void run()}>
      {action.label}
    </Button>
  );

  return (
    <span class="rt-action">
      {action.input ? (
        <form
          class="rt-action__form"
          onSubmit={(event) => {
            event.preventDefault();
            void run();
          }}
        >
          <input class="rt-field" value={text} placeholder={action.input.placeholder} aria-label={action.label} onInput={(event) => setText(event.currentTarget.value)} />
          {button}
        </form>
      ) : (
        button
      )}
      {error && <span class="rt-action__error">{error}</span>}
    </span>
  );
};
