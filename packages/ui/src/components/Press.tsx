import type { CardAction, Result } from "@routines/sdk";
import { useState } from "preact/hooks";
import { Button } from "./Button.tsx";

type Props = {
  label: string;
  style?: CardAction["style"];
  input?: { placeholder: string };
  busy: boolean;
  shortcut?: string;
  run: (text: string | undefined) => Promise<Result<string | null>>;
  onResult?: (result: Result<string | null>) => void;
};

// A button, or a field and a button when the press needs text. ActionButton and TransitionButton share it.
export const Press = ({ label, style, input, busy, shortcut, run, onResult }: Props) => {
  const [text, setText] = useState("");
  const [error, setError] = useState<string>();
  const blank = input !== undefined && text.trim() === "";
  const press = async () => {
    if (busy || blank) return;
    const result = await run(input ? text : undefined);
    // You pressed Cancel in the host dialog, so the page needs no message.
    setError(result.ok || result.error === "Cancelled." ? undefined : result.error);
    if (result.ok) setText("");
    onResult?.(result);
  };
  const button = (
    <Button variant={style ?? "normal"} disabled={busy || blank} shortcut={shortcut} onClick={() => void press()}>
      {label}
    </Button>
  );

  return (
    <span class="rt-action">
      {input ? (
        <form
          class="rt-action__form"
          onSubmit={(event) => {
            event.preventDefault();
            void press();
          }}
        >
          <input class="rt-field" value={text} placeholder={input.placeholder} aria-label={label} onInput={(event) => setText(event.currentTarget.value)} />
          {button}
        </form>
      ) : (
        button
      )}
      {error && <span class="rt-action__error">{error}</span>}
    </span>
  );
};
