import { host, type ActionEvent, type Column } from "./host.ts";
import { log } from "./log.ts";
import { join } from "./path.ts";
import { err, ok, type Result } from "./result.ts";

// The id of the item action `{ "id": "done", "label": "Done", "target": "item" }` in a manifest.
export const DONE_ACTION_ID = "done";

// Moves a card. A card that is gone, or already in the column, stays as it is.
export const moveCard = async (id: string, column: Column, status?: string): Promise<Result<boolean>> => {
  const cards = await host().board.list();
  if (!cards.ok) return cards;
  const stored = cards.value.find((card) => card.id === id);
  if (!stored || stored.column === column) return ok(false);
  const { updatedAt: _, ...card } = stored;
  const moved = await host().board.upsert({ ...card, column, ...(status === undefined ? {} : { status }) });
  return moved.ok ? ok(true) : moved;
};

// The Done action only moves the card, so it cannot race with the ledger writes of a run.
export const onDoneAction = async ({ cardId, actionId }: ActionEvent): Promise<Result<string>> => {
  if (actionId !== DONE_ACTION_ID) return err(`unknown action: ${actionId}`);
  const moved = await moveCard(cardId, "done");
  return moved.ok ? ok("Done.") : moved;
};

// Broken notes must not stop a routine, so it runs without them.
export const myNotes = async (): Promise<string[]> => {
  const notes = await host().notes.list();
  if (notes.ok) return notes.value.map(({ text }) => text);
  log(`notes: ${notes.error}`);
  return [];
};

// A card body is Markdown, so text from outside cannot add a link, an image or formatting.
export const escapeMarkdown = (text: string) => text.replace(/[\\`*_[\]()<>#!|~]/g, "\\$&");

export const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export const expandHome = (path: string, home = host().info.home) => (path === "~" ? home : path.startsWith("~/") ? join(home, path.slice(2)) : path);
