import type { ComponentChildren } from "preact";
import { useEffect } from "preact/hooks";

type WorkspaceProps = { detail?: ComponentChildren; children: ComponentChildren };

// The main view on the left, and the detail of the selected item on the right while one is selected.
export const Workspace = ({ detail, children }: WorkspaceProps) => (
  <div class="rt-workspace" data-detail={Boolean(detail)}>
    <div class="rt-workspace__main">{children}</div>
    {detail}
  </div>
);

type PaneProps = { title: string; onClose: () => void; children: ComponentChildren };

const isTyping = (target: EventTarget | null) => target instanceof HTMLElement && (target.isContentEditable || ["INPUT", "TEXTAREA"].includes(target.tagName));

// A side panel that stays in view while the page scrolls. Escape and the close button close it.
export const DetailPane = ({ title, onClose, children }: PaneProps) => {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !isTyping(event.target)) onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <aside class="rt-pane" aria-label={title}>
      <header class="rt-pane__head">
        <h2 class="rt-pane__title">{title}</h2>
        <button type="button" class="rt-pane__close" aria-label="Close" title="Close (Esc)" onClick={onClose}>
          ×
        </button>
      </header>
      <div class="rt-pane__body">{children}</div>
    </aside>
  );
};
