routines.definePlugin({
  run: async ({ settings, trigger }) => {
    await new Promise((resolve) => setTimeout(resolve, 10));
    const url = new URL("https://example.com/a?b=1");
    const bytes = new TextEncoder().encode("é");
    await routines.fs.writeText(`${routines.info.stateDir}/echo.txt`, `${trigger}:${settings.greeting}:${url.searchParams.get("b")}:${bytes.length}:${btoa("hi")}`);
    const denied = await routines.exec(["rm", "-rf", "/tmp/routines-never"]);
    const outside = await routines.fs.readText("/etc/hosts");
    await routines.board.upsert({ id: "c1", title: "Hello", column: "needs-you", status: [denied.error, outside.error].join(" | ") });
    await routines.notify({ title: "Hi", body: "There", cardId: "c1" });
    await routines.page.publish([{ type: "status", state: "ok", label: "Up" }, { type: "markdown", text: "Hello" }]);
    const page = await routines.page.get();
    if (page.value?.blocks.length !== 2) throw new Error("page.get did not return the page");
    console.log("logged", { a: 1 });
    return routines.exec(["echo", "hi"]);
  },
  onAction: async ({ cardId, actionId, text }) => {
    if (actionId === "boom") throw new Error("boom");
    if (actionId === "later") {
      await routines.runSoon(10);
      await routines.runSoon(60000);
      return { ok: true, value: "later" };
    }
    if (actionId === "slow") await new Promise(() => {});
    const card = (await routines.board.list()).value.find((entry) => entry.id === cardId);
    await routines.board.upsert({ ...card, column: "done" });
    return { ok: true, value: `moved ${text ?? ""}`.trim() };
  },
  onPluginAction: async ({ actionId, text }) => ({ ok: true, value: `${actionId} ${text}` }),
});
