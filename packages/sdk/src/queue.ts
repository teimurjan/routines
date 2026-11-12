import { z } from "zod";
import { readStateFile, updateStateFile } from "./state-file.ts";
import type { Result } from "./result.ts";

// A list in a shared state file. One plugin pushes items and another removes each item after it handled that item.
export type Queue<Item> = {
  read: () => Promise<Result<Item[]>>;
  push: (items: Item[]) => Promise<Result<void>>;
  remove: (item: Item) => Promise<Result<void>>;
};

// A key drops the item that an overlapping search finds twice.
export const queueIn = <Schema extends z.ZodType>(file: string, schema: Schema, keyOf: (item: z.infer<Schema>) => string): Queue<z.infer<Schema>> => {
  const list = z.array(schema);
  const update = (change: (items: z.infer<Schema>[]) => z.infer<Schema>[]) =>
    updateStateFile(file, list, [], (items: z.infer<Schema>[]) => ({ next: change(items), output: undefined as void }));
  return {
    read: () => readStateFile(file, list, []),
    push: (fresh) =>
      update((items) => {
        const known = new Set(items.map(keyOf));
        return [...items, ...fresh.filter((item) => !known.has(keyOf(item)))];
      }),
    remove: (item) => update((items) => items.filter((entry) => keyOf(entry) !== keyOf(item))),
  };
};
