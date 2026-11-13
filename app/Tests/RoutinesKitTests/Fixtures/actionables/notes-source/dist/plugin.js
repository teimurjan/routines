const output = {
  type: "object",
  required: ["items"],
  properties: { items: { type: "array", items: { type: "object", required: ["key", "title"], properties: { key: { type: "string" }, title: { type: "string" }, kind: { type: "string" } } } } },
};

routines.definePlugin({
  pollRequest: async ({ cursor }) => ({ ok: true, value: { prompt: "List the notes after the cursor.", input: { cursor }, output } }),
  onPoll: async ({ cursor, output }) => {
    const items = (output && output.items ? output.items : []).map(({ key, title, kind }) => ({ dedupeKey: key, kind: kind || "note", title, data: {} }));
    return { ok: true, value: { items, cursor: items.length > 0 ? { after: items[items.length - 1].dedupeKey } : cursor } };
  },
});
