import type { StoredCard } from "@routines/sdk";
import { ActionButton } from "./ActionButton.tsx";

// The item action `done` of the manifest, on an item that needs you.
export const DoneButton = ({ item }: { item: StoredCard }) => (item.column === "needs-you" ? <ActionButton actionId="done" cardId={item.id} /> : null);
