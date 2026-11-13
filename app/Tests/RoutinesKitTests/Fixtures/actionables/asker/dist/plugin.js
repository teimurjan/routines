routines.definePlugin({
  run: async () => {
    const bugs = await routines.actionables.list({ states: ["new"] });
    for (const bug of bugs.value) {
      const question = { text: "Which key?", transition: "answer", session: { id: "s-1", cwd: "/tmp" } };
      const moved = await routines.actionables.move(bug.id, { transition: "ask", to: "waiting-on-you", question });
      if (!moved.ok) return moved;
    }
    return { ok: true, value: `asked ${bugs.value.length}` };
  },
  onTransition: async ({ transition, text, session, history }) => {
    console.log(`session ${session ? session.id : "none"} history ${history.length}`);
    if (transition === "answer") return { ok: true, value: { to: "working", status: text } };
    if (transition === "merge") return { ok: true, value: { to: "done", status: "merged" } };
    if (transition === "approve") return { ok: true, value: { to: "done", status: "approved" } };
    if (transition === "drop") return { ok: true, value: { to: "dropped", status: "dropped" } };
    return { ok: false, error: `unknown transition ${transition}` };
  },
});
