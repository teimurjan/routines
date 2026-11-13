// The shapes of the kinds that a plugin declares, as the host reads them in dist/kinds.json. See specs/004-actionables/contracts/actionables.md.
import { z } from "zod";

export type KindSchemas = Record<string, Record<string, unknown>>;

// A plugin can resolve its own copy of Zod, so the check looks at the shape and not at the class.
const isZodSchema = (value: unknown): value is z.ZodType => typeof value === "object" && value !== null && "_zod" in value && "safeParse" in value;

// Each Zod export of src/kinds.ts by its name. The host does not know the meta-schema that Zod names, so `$schema` goes.
export const kindSchemas = (exports: Record<string, unknown>): KindSchemas =>
  Object.fromEntries(
    Object.entries(exports)
      .filter((entry): entry is [string, z.ZodType] => isZodSchema(entry[1]))
      .map(([name, schema]) => {
        const { $schema: _, ...rest } = z.toJSONSchema(schema);
        return [name, rest];
      }),
  );

// The kinds of the manifest that src/kinds.ts does not export, so the host would refuse the plugin.
export const missingKinds = (declared: string[], schemas: KindSchemas) => declared.filter((kind) => !(kind in schemas));
