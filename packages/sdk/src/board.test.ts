import { expect, test } from "bun:test";
import { moveCard, onDoneAction } from "./board.ts";
import { installTestHost } from "./testing.ts";

test("Done moves the card, and a second press changes nothing", async () => {
  const { host, cards } = installTestHost();
  await host.board.upsert({ id: "a", title: "A", column: "needs-you" });
  expect(await onDoneAction({ cardId: "a", actionId: "done" })).toEqual({ ok: true, value: "Done." });
  expect(cards.get("a")).toMatchObject({ column: "done" });
  expect(await moveCard("a", "done")).toEqual({ ok: true, value: false });
});

test("Done refuses another action id", async () => {
  installTestHost();
  expect(await onDoneAction({ cardId: "a", actionId: "stop" })).toEqual({ ok: false, error: "unknown action: stop" });
});
