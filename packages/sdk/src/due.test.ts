import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { isDailyDue, latestDailySlot, runDailyWhenDue } from "./due.ts";
import { err, ok } from "./result.ts";
import { installTestHost } from "./testing.ts";

installTestHost();

const HOUR = 21;
const at = (day: number, hour: number, minute = 0) => new Date(2026, 10, day, hour, minute);
const stateFile = () => join(mkdtempSync(join(tmpdir(), "due-test-")), "last");

test("the slot is yesterday before its hour and today from its hour", () => {
  expect(latestDailySlot(at(7, 20, 59), HOUR)).toEqual(at(6, HOUR));
  expect(latestDailySlot(at(7, HOUR), HOUR)).toEqual(at(7, HOUR));
});

test("a first run is due at once", () => {
  expect(isDailyDue(undefined, at(7, 10), HOUR)).toBe(true);
});

test("a run that the Mac slept through or that failed is due the next morning", () => {
  expect(isDailyDue(at(5, HOUR, 14), at(7, 2, 30), HOUR)).toBe(true);
});

test("a finished run is not due again until the next slot", () => {
  expect(isDailyDue(at(6, HOUR, 14), at(6, HOUR, 30), HOUR)).toBe(false);
  expect(isDailyDue(at(6, HOUR, 14), at(7, 20, 30), HOUR)).toBe(false);
  expect(isDailyDue(at(6, HOUR, 14), at(7, HOUR), HOUR)).toBe(true);
});

test("a catch-up run in the morning does not end the slot of that evening", () => {
  expect(isDailyDue(at(7, 8), at(7, HOUR), HOUR)).toBe(true);
});

test("a failed run stays due and a finished run does not", async () => {
  const file = stateFile();
  let runs = 0;
  const failing = async () => {
    runs += 1;
    return err("offline");
  };
  const finishing = async () => {
    runs += 1;
    return ok(undefined);
  };
  await runDailyWhenDue(file, HOUR, failing);
  await runDailyWhenDue(file, HOUR, finishing);
  await runDailyWhenDue(file, HOUR, finishing);
  expect(runs).toBe(2);
});
