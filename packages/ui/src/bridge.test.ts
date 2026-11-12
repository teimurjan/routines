import { afterEach, beforeEach, expect, test } from "bun:test";
import { actionOf, bridge, connect, imageUrl, type Snapshot } from "./bridge.ts";

type Sent = { type: string; [field: string]: unknown };

const snapshot = (title: string): Snapshot => ({
  plugin: { id: "tickets", name: "Tickets", color: "#DB2777" },
  items: [{ id: "c1", title, column: "needs-you", updatedAt: "2026-11-09T10:00:00.000Z" }],
  page: null,
  actions: [],
  pending: { items: [], plugin: false },
  status: null,
  appearance: { scheme: "light", accent: "#007AFF" },
});

let sent: Sent[] = [];
let answer: (message: Sent) => unknown = () => ({ ok: true, value: null });

// A fake web view: `window` dispatches events, and the message handler records each message.
beforeEach(() => {
  sent = [];
  const target = new EventTarget() as unknown as Window;
  target.webkit = {
    messageHandlers: {
      routines: {
        postMessage: async (message) => {
          sent.push(message as Sent);
          return answer(message as Sent);
        },
      },
    },
  };
  globalThis.window = target as Window & typeof globalThis;
});

afterEach(() => {
  answer = () => ({ ok: true, value: null });
});

test("a call resolves with the reply of the host", async () => {
  answer = () => ({ ok: true, value: "Moved to Trash." });
  expect(await bridge.perform("c1", "trash")).toEqual({ ok: true, value: "Moved to Trash." });
  expect(sent).toEqual([{ type: "perform", cardId: "c1", actionId: "trash" }]);
});

test("an error reply and a cancelled action are errors, not exceptions", async () => {
  answer = () => ({ ok: false, error: "Cancelled." });
  expect(await bridge.performPluginAction("trash-numbers", "41")).toEqual({ ok: false, error: "Cancelled." });
  expect(sent[0]).toEqual({ type: "performPluginAction", actionId: "trash-numbers", text: "41" });
  answer = () => {
    throw new Error("the plugin UI closed");
  };
  expect(await bridge.openLink("https://example.com")).toEqual({ ok: false, error: "the plugin UI closed" });
});

test("connect takes the first snapshot, sends ready, and follows each snapshot event", async () => {
  answer = (message) => (message.type === "snapshot" ? { ok: true, value: snapshot("First") } : { ok: true, value: null });
  const seen: string[] = [];
  const stop = connect((value) => seen.push(value.items[0]?.title ?? ""), () => {});
  await Bun.sleep(0);
  window.dispatchEvent(new CustomEvent("routines", { detail: { type: "snapshot", value: snapshot("Second") } }));
  window.dispatchEvent(new CustomEvent("routines", { detail: { type: "unknown", value: 1 } }));
  stop();
  window.dispatchEvent(new CustomEvent("routines", { detail: { type: "snapshot", value: snapshot("After stop") } }));
  expect(seen).toEqual(["First", "Second"]);
  expect(sent.map(({ type }) => type)).toEqual(["snapshot", "ready"]);
});

test("outside the app each call fails with the reason", async () => {
  delete window.webkit;
  expect(await bridge.snapshot()).toEqual({ ok: false, error: "the page runs outside the Routines app" });
});

test("an image URL encodes the whole path, spaces and slashes too", () => {
  expect(imageUrl("/Users/me/state/a car.jpg")).toBe("/_image/%2FUsers%2Fme%2Fstate%2Fa%20car.jpg");
});

test("actionOf finds a manifest action by its id", () => {
  const value = { ...snapshot("First"), actions: [{ id: "done", label: "Done", target: "item" as const }] };
  expect(actionOf(value, "done")?.label).toBe("Done");
  expect(actionOf(value, "delete-all")).toBeUndefined();
  expect(actionOf(undefined, "done")).toBeUndefined();
});
