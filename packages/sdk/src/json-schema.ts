import { z } from "zod";

// The CLI validator and the host do not know the draft 2020-12 meta-schema that Zod names, so it goes.
export const jsonSchemaOf = (schema: z.ZodType): Record<string, unknown> => {
  const { $schema: _, ...rest } = z.toJSONSchema(schema);
  return rest;
};
