import type { ComponentChildren } from "preact";

type Props = {
  id?: string;
  title: string;
  // A short mark before the title, for example an issue number.
  leading?: string;
  // Plain text, at most 2 lines.
  preview?: string;
  meta?: ComponentChildren;
  // Buttons that act without opening the card.
  footer?: ComponentChildren;
  selected?: boolean;
  // A dot in the accent color, for an item that needs you.
  unread?: boolean;
  // One line with the meta on the right, for long lists.
  dense?: boolean;
  onOpen?: () => void;
};

// A compact card of a board column. A press or the Return key calls `onOpen`.
export const BoardCard = ({ id, title, leading, preview, meta, footer, selected = false, unread = false, dense = false, onOpen }: Props) => (
  <article
    class="rt-board-card"
    id={id}
    data-selected={selected}
    data-dense={dense}
    data-openable={onOpen !== undefined}
    tabIndex={onOpen ? 0 : undefined}
    onClick={onOpen}
    onKeyDown={(event) => {
      if (event.key === "Enter" && event.target === event.currentTarget) onOpen?.();
    }}
  >
    <div class="rt-board-card__main">
      <h3 class="rt-board-card__title">
        {unread && <span class="rt-board-card__unread" aria-label="Needs you" />}
        {leading && <span class="rt-board-card__leading">{leading}</span>}
        <span class="rt-board-card__text">{title}</span>
      </h3>
      {preview && <p class="rt-board-card__preview">{preview}</p>}
      {meta && <div class="rt-board-card__meta">{meta}</div>}
    </div>
    {footer && (
      // A press on a button must not open the card as well.
      <div class="rt-board-card__footer" onClick={(event) => event.stopPropagation()}>
        {footer}
      </div>
    )}
  </article>
);
