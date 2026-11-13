routines.definePlugin({
  run: async () => {
    const working = await routines.actionables.list({ states: ["working"] });
    for (const note of working.value) {
      const handed = await routines.actionables.handoff(note.id, { state: "new", kind: "bug", data: { repo: "demo", details: "x" } });
      if (!handed.ok) return handed;
    }
    return { ok: true, value: `handed ${working.value.length}` };
  },
  onTransition: async ({ transition }) => ({ ok: true, value: { to: transition === "send" ? "done" : "working", status: `${transition} done` } }),
});
