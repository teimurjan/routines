import { expect, test } from "bun:test";
import { parseMarkdown, previewOf, type Inline } from "./markdown.ts";

const text = (value: string): Inline => ({ type: "text", text: value });

test("headings, list items and paragraphs become blocks", () => {
  expect(parseMarkdown("# One\n## Two\n### Three\n- item\n1. first\nA paragraph.\n\n")).toEqual([
    { type: "heading", level: 1, inline: [text("One")] },
    { type: "heading", level: 2, inline: [text("Two")] },
    { type: "heading", level: 3, inline: [text("Three")] },
    { type: "item", inline: [text("item")] },
    { type: "item", inline: [text("first")] },
    { type: "paragraph", inline: [text("A paragraph.")] },
  ]);
});

test("a deeper heading counts as level 3", () => {
  expect(parseMarkdown("##### Deep")).toEqual([{ type: "heading", level: 3, inline: [text("Deep")] }]);
});

test("links, bold, italic and code become inline nodes", () => {
  expect(parseMarkdown("See [the PR](https://github.com/a/b/pull/1), **now**, _soon_ and `bun test`.")).toEqual([
    {
      type: "paragraph",
      inline: [
        text("See "),
        { type: "link", url: "https://github.com/a/b/pull/1", children: [text("the PR")] },
        text(", "),
        { type: "strong", children: [text("now")] },
        text(", "),
        { type: "emphasis", children: [text("soon")] },
        text(" and "),
        { type: "code", text: "bun test" },
        text("."),
      ],
    },
  ]);
});

test("a backslash escape stays text, so escaped outside text cannot add a link", () => {
  expect(parseMarkdown("A \\[promo\\]\\(https://evil.example\\).")).toEqual([{ type: "paragraph", inline: [text("A [promo](https://evil.example).")] }]);
});

test("a link that is not http or https becomes text", () => {
  expect(parseMarkdown("[click](javascript:alert(1))")).toEqual([{ type: "paragraph", inline: [text("click")] }]);
});

test("HTML stays text", () => {
  expect(parseMarkdown("<b>bold</b>")).toEqual([{ type: "paragraph", inline: [text("<b>bold</b>")] }]);
});

test("a fenced block keeps its lines as they are", () => {
  expect(parseMarkdown("The fix:\n```diff\n- old **x**\n+ new\n```\nDone.")).toEqual([
    { type: "paragraph", inline: [text("The fix:")] },
    { type: "code", text: "- old **x**\n+ new" },
    { type: "paragraph", inline: [text("Done.")] },
  ]);
  expect(parseMarkdown("```\nopen")).toEqual([{ type: "code", text: "open" }]);
});

test("a preview is the plain text of the first block that is not code", () => {
  expect(previewOf("```diff\n+a\n```\n**Fix** the [login](https://x.dev) `bug`\nMore.")).toBe("Fix the login bug");
  expect(previewOf("```\nonly code\n```")).toBe("");
});
