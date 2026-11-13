import Foundation

/// The host script of each plugin UI. A Command-click or Control-click on an item asks the app to open a thread about it.
/// It runs in its own content world, so the page cannot call it, and it acts only on trusted clicks.
enum AskScript {
    static let handler = "routinesAsk"

    /// The host sets `window.routinesCards` in this world to the ids of the items of the plugin.
    static let source = #"""
        (() => {
          const held = (event) => event.metaKey || event.ctrlKey;
          let pointer = null;
          let marked = null;
          let swallowUntil = 0;

          const cardOf = (node) => {
            const cards = window.routinesCards;
            if (!cards) return null;
            for (let element = node instanceof Element ? node : node?.parentElement ?? null; element; element = element.parentElement) {
              const id = element.dataset?.cardId || element.id;
              if (id && cards.has(id)) return { element, id };
            }
            return null;
          };

          const unmark = () => {
            if (!marked) return;
            const { style } = marked.element;
            style.outline = marked.outline;
            style.outlineOffset = marked.offset;
            style.cursor = marked.cursor;
            marked = null;
          };

          const mark = (found) => {
            if (found?.element === marked?.element) return;
            unmark();
            if (!found) return;
            const { style } = found.element;
            marked = { element: found.element, outline: style.outline, offset: style.outlineOffset, cursor: style.cursor };
            style.outline = "2px solid var(--accent, AccentColor)";
            style.outlineOffset = "2px";
            style.cursor = "alias";
          };

          const refresh = (event) => mark(held(event) ? cardOf(pointer) : null);

          addEventListener("mousemove", (event) => {
            pointer = event.target;
            refresh(event);
          }, true);
          addEventListener("keydown", refresh, true);
          addEventListener("keyup", refresh, true);
          addEventListener("blur", unmark);

          addEventListener("mousedown", (event) => {
            if (!event.isTrusted || event.button !== 0 || !held(event)) return;
            const found = cardOf(event.target);
            if (!found) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            unmark();
            swallowUntil = Date.now() + 600;
            window.webkit.messageHandlers.routinesAsk.postMessage({ cardId: found.id });
          }, true);

          // The rest of the click must not open the item or a menu as well.
          for (const type of ["mouseup", "contextmenu", "click"]) {
            addEventListener(type, (event) => {
              if (Date.now() > swallowUntil) return;
              event.preventDefault();
              event.stopImmediatePropagation();
              if (type === "click") swallowUntil = 0;
            }, true);
          }
        })();
        """#
}
