import type { ComponentChildren } from "preact";
import type { Tone } from "../groups.ts";

export type BoardColumn<Item> = { id: string; title: string; tone?: Tone; items: Item[] };

type Props<Item> = {
  columns: BoardColumn<Item>[];
  keyOf: (item: Item) => string;
  renderItem: (item: Item) => ComponentChildren;
  // The text of a column without items.
  empty?: string;
};

// Columns side by side, each with a colored dot, a title, a count and its items. A narrow window scrolls the board sideways.
export const Board = <Item,>({ columns, keyOf, renderItem, empty = "Nothing here." }: Props<Item>) => (
  <div class="rt-board">
    {columns.map(({ id, title, tone = "neutral", items }) => (
      <section class="rt-board__column" key={id} aria-label={title}>
        <h2 class="rt-board__head">
          <span class="rt-board__dot" data-tone={tone} aria-hidden="true" />
          <span class="rt-board__title">{title}</span>
          <span class="rt-board__count">{items.length}</span>
        </h2>
        <div class="rt-board__items">
          {items.length === 0 ? <p class="rt-board__empty">{empty}</p> : items.map((item) => <div key={keyOf(item)}>{renderItem(item)}</div>)}
        </div>
      </section>
    ))}
  </div>
);
