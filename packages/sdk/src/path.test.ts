import { expect, test } from "bun:test";
import { basename, dirname, join } from "./path.ts";

test("join and dirname match node:path for the forms that plugins use", () => {
  expect(join("/a/b", "../c", "d.json")).toBe("/a/c/d.json");
  expect(join("a", "", "./b")).toBe("a/b");
  expect(dirname("/a/b/c.json")).toBe("/a/b");
  expect(dirname("/a")).toBe("/");
  expect(basename("/a/b/c.json")).toBe("c.json");
});
