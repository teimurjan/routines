import type { Column, StoredCard } from "@routines/sdk";

export const STATE_ORDER: Column[] = ["needs-you", "working", "planned", "failed", "done"];

export const STATE_TITLES: Record<Column, string> = {
  "needs-you": "Needs you",
  working: "In progress",
  planned: "Planned",
  failed: "Failed",
  done: "Done",
};

// The color of the dot in the head of a board column.
export type Tone = "accent" | "warning" | "danger" | "success" | "neutral";

export const STATE_TONES: Record<Column, Tone> = {
  "needs-you": "accent",
  working: "warning",
  planned: "neutral",
  failed: "danger",
  done: "success",
};

export const newestFirst = (left: StoredCard, right: StoredCard) => right.updatedAt.localeCompare(left.updatedAt);

// The items by state, what needs you first. A group with no items is left out.
export const byState = (items: StoredCard[]) =>
  STATE_ORDER.map((state) => ({ state, items: items.filter((item) => item.column === state).sort(newestFirst) })).filter(({ items: group }) => group.length > 0);
