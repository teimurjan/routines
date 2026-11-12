import type { ComponentChildren } from "preact";

type Props = {
  title: string;
  // Plain text. A card shows the text of an item as text, never as HTML.
  body?: string;
  status?: string;
  meta?: ComponentChildren;
  footer?: ComponentChildren;
  selected?: boolean;
  onClick?: () => void;
};

export const Card = ({ title, body, status, meta, footer, selected = false, onClick }: Props) => (
  <article class="rt-card" data-selected={selected} onClick={onClick}>
    <div class="rt-card__content">
      <h3 class="rt-card__title">{title}</h3>
      {body && <p class="rt-card__body">{body}</p>}
      {status && (
        <p class="rt-card__status" data-error={status.startsWith("Error")}>
          {status}
        </p>
      )}
      {meta && <div class="rt-card__meta">{meta}</div>}
    </div>
    {footer && <footer class="rt-card__footer">{footer}</footer>}
  </article>
);
