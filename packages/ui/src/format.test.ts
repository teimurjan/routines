import { expect, test } from "bun:test";
import { timeAgo } from "./format.ts";

const NOW = new Date("2026-11-09T12:00:00.000Z");

test("a recent time shows as minutes, hours or days, and an older one as its day", () => {
  expect(timeAgo("2026-11-09T11:59:30.000Z", NOW)).toBe("now");
  expect(timeAgo("2026-11-09T11:15:00.000Z", NOW)).toBe("45m");
  expect(timeAgo("2026-11-09T02:00:00.000Z", NOW)).toBe("10h");
  expect(timeAgo("2026-11-03T12:00:00.000Z", NOW)).toBe("6d");
  expect(timeAgo("2026-10-01T12:00:00.000Z", NOW)).toBe("Oct 1");
  expect(timeAgo("not a date", NOW)).toBe("");
});
