import type { CardAction } from "@routines/sdk";
import type { ComponentChildren } from "preact";

type Props = {
  variant?: NonNullable<CardAction["style"]>;
  disabled?: boolean;
  // A key that presses this button. The button shows it, so each key has a visible button with the same label.
  shortcut?: string;
  onClick: () => void;
  children: ComponentChildren;
};

export const Button = ({ variant = "normal", disabled = false, shortcut, onClick, children }: Props) => (
  <button type="button" class="rt-button" data-variant={variant} disabled={disabled} onClick={onClick}>
    {children}
    {shortcut && <kbd class="rt-button__key">{shortcut}</kbd>}
  </button>
);
