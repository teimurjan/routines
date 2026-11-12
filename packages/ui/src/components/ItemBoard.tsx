import type { StoredCard } from "@routines/sdk";
import type { ComponentChildren } from "preact";
import { useCallback, useState } from "preact/hooks";
import { bridge, imageUrl } from "../bridge.ts";
import { shortDay, timeAgo } from "../format.ts";
import { byState, STATE_TITLES, STATE_TONES } from "../groups.ts";
import { useFocusedItem } from "../hooks.ts";
import { previewOf } from "../markdown.ts";
import { Board, type BoardColumn } from "./Board.tsx";
import { BoardCard } from "./BoardCard.tsx";
import { DetailPane, Workspace } from "./DetailPane.tsx";
import { Markdown } from "./Markdown.tsx";
import { Pill } from "./Pill.tsx";
import { ProgressRing } from "./ProgressRing.tsx";

const Progress = ({ value }: { value: number }) => (
  <Pill>
    <ProgressRing value={value} />
    {Math.round(value * 100)}%
  </Pill>
);

// Everything of one item: the image, the status, the date, the tags, the links, the body and the actions.
export const ItemDetail = ({ item, children }: { item: StoredCard; children?: ComponentChildren }) => {
  const image = item.images?.[0];
  const links = item.links ?? [];
  return (
    <div class="rt-detail">
      {image && <img class="rt-detail__image" src={imageUrl(image)} alt="" loading="lazy" />}
      <div class="rt-detail__meta">
        <span>{STATE_TITLES[item.column]}</span>
        <span>{shortDay(item.date ?? item.updatedAt)}</span>
        {item.tags?.map((tag) => <Pill key={tag}>{tag}</Pill>)}
        {item.progress !== undefined && <Progress value={item.progress} />}
      </div>
      {item.status && (
        <p class="rt-detail__status" data-error={item.status.startsWith("Error")}>
          {item.status}
        </p>
      )}
      <div class="rt-detail__actions">
        {children}
        {links.length > 0 && <span class="rt-detail__spacer" />}
        {links.map((link) => (
          <button type="button" class="rt-link" key={link.url} title={link.url} onClick={() => void bridge.openLink(link.url)}>
            {link.label} ↗
          </button>
        ))}
      </div>
      {item.body && <Markdown text={item.body} />}
    </div>
  );
};

type TileProps = { item: StoredCard; selected: boolean; onOpen: () => void; leading?: string; footer?: ComponentChildren };

// The compact card of an item on a board.
export const ItemTile = ({ item, selected, onOpen, leading, footer }: TileProps) => (
  <BoardCard
    id={item.id}
    title={item.title}
    leading={leading}
    preview={item.status?.startsWith("Error") ? item.status : previewOf(item.body ?? "")}
    selected={selected}
    unread={item.column === "needs-you"}
    onOpen={onOpen}
    footer={footer}
    meta={
      <>
        {item.tags?.slice(0, 2).map((tag) => <Pill key={tag}>{tag}</Pill>)}
        {item.progress !== undefined && <Progress value={item.progress} />}
        <span class="rt-board-card__time">{timeAgo(item.date ?? item.updatedAt)}</span>
      </>
    }
  />
);

type Props = {
  items: StoredCard[];
  empty: string;
  // The columns of the board. By default, one column per state that has items.
  columns?: (items: StoredCard[]) => BoardColumn<StoredCard>[];
  // The buttons in the detail of an item.
  actions?: (item: StoredCard) => ComponentChildren;
  // The buttons on the card itself, for a press without opening it.
  quickActions?: (item: StoredCard) => ComponentChildren;
  leading?: (item: StoredCard) => string | undefined;
  sort?: (left: StoredCard, right: StoredCard) => number;
};

const columnsByState = (items: StoredCard[]): BoardColumn<StoredCard>[] =>
  byState(items).map(({ state, items: group }) => ({ id: state, title: STATE_TITLES[state], tone: STATE_TONES[state], items: group }));

// The items as a board. A press on a card opens its detail at the side, and a notification of an item opens it too.
export const ItemBoard = ({ items, empty, columns = columnsByState, actions, quickActions, leading, sort }: Props) => {
  const [selectedId, setSelectedId] = useState<string>();
  useFocusedItem(useCallback((cardId: string) => setSelectedId(cardId), []));
  const close = useCallback(() => setSelectedId(undefined), []);

  if (items.length === 0) return <p class="rt-empty">{empty}</p>;
  const selected = items.find(({ id }) => id === selectedId);
  const shown = columns(items).map((column) => (sort ? { ...column, items: [...column.items].sort(sort) } : column));

  return (
    <Workspace
      detail={
        selected && (
          <DetailPane title={selected.title} onClose={close}>
            <ItemDetail item={selected}>{actions?.(selected)}</ItemDetail>
          </DetailPane>
        )
      }
    >
      <Board
        columns={shown}
        keyOf={({ id }) => id}
        renderItem={(item) => (
          <ItemTile
            item={item}
            selected={item.id === selectedId}
            leading={leading?.(item)}
            footer={quickActions?.(item)}
            onOpen={() => setSelectedId(item.id === selectedId ? undefined : item.id)}
          />
        )}
      />
    </Workspace>
  );
};
