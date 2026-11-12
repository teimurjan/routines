// A parser of the Markdown that plugins write. It returns nodes, never HTML. See "Markdown node" in specs/003-custom-ui-everywhere/data-model.md.

export type Inline =
  | { type: "text"; text: string }
  | { type: "strong" | "emphasis"; children: Inline[] }
  | { type: "code"; text: string }
  | { type: "link"; url: string; children: Inline[] };

export type Block =
  | { type: "heading"; level: 1 | 2 | 3; inline: Inline[] }
  | { type: "item"; inline: Inline[] }
  | { type: "paragraph"; inline: Inline[] }
  // The lines of a fenced block, such as a diff, as they are.
  | { type: "code"; text: string };

const SAFE_URL = /^https?:\/\//i;
const WORD = /[\p{L}\p{N}]/u;

// Adjacent text nodes merge, so a test and a renderer see one node per run of text.
const pushText = (nodes: Inline[], text: string) => {
  if (!text) return;
  const last = nodes.at(-1);
  if (last?.type === "text") nodes[nodes.length - 1] = { type: "text", text: last.text + text };
  else nodes.push({ type: "text", text });
};

const append = (nodes: Inline[], more: Inline[]) => {
  for (const node of more) node.type === "text" ? pushText(nodes, node.text) : nodes.push(node);
};

// The index of `marker` at or after `from`, outside a backslash escape, or -1.
const closing = (source: string, marker: string, from: number) => {
  for (let index = from; index < source.length; index++) {
    if (source[index] === "\\") index++;
    else if (source.startsWith(marker, index)) return index;
  }
  return -1;
};

// The index of the parenthesis that closes the one before `from`, so a URL can hold parentheses.
const closingParen = (source: string, from: number) => {
  let depth = 1;
  for (let index = from; index < source.length; index++) {
    if (source[index] === "(") depth++;
    if (source[index] === ")" && --depth === 0) return index;
  }
  return -1;
};

const isWordAt = (source: string, index: number) => index >= 0 && index < source.length && WORD.test(source[index] ?? "");

export const parseInline = (source: string): Inline[] => {
  const nodes: Inline[] = [];
  let index = 0;
  while (index < source.length) {
    const char = source[index] ?? "";
    if (char === "\\" && index + 1 < source.length) {
      pushText(nodes, source[index + 1] ?? "");
      index += 2;
      continue;
    }
    if (char === "`") {
      const end = source.indexOf("`", index + 1);
      if (end > index) {
        nodes.push({ type: "code", text: source.slice(index + 1, end) });
        index = end + 1;
        continue;
      }
    }
    if (source.startsWith("**", index)) {
      const end = closing(source, "**", index + 2);
      if (end > index + 2) {
        nodes.push({ type: "strong", children: parseInline(source.slice(index + 2, end)) });
        index = end + 2;
        continue;
      }
    }
    if ((char === "_" || char === "*") && !isWordAt(source, index - 1)) {
      const end = closing(source, char, index + 1);
      if (end > index + 1 && !isWordAt(source, end + 1)) {
        nodes.push({ type: "emphasis", children: parseInline(source.slice(index + 1, end)) });
        index = end + 1;
        continue;
      }
    }
    if (char === "[") {
      const labelEnd = closing(source, "]", index + 1);
      if (labelEnd > index && source[labelEnd + 1] === "(") {
        const urlEnd = closingParen(source, labelEnd + 2);
        if (urlEnd > labelEnd) {
          const url = source.slice(labelEnd + 2, urlEnd).trim();
          const children = parseInline(source.slice(index + 1, labelEnd));
          if (SAFE_URL.test(url)) nodes.push({ type: "link", url, children });
          else append(nodes, children);
          index = urlEnd + 1;
          continue;
        }
      }
    }
    pushText(nodes, char);
    index++;
  }
  return nodes;
};

const HEADING = /^(#{1,6})\s+(.+)$/;
const ITEM = /^(?:[-*+]|\d+\.)\s+(.+)$/;

const FENCE = /^\s*```/;

const lineBlock = (raw: string): Block[] => {
  const line = raw.trim();
  if (!line) return [];
  const heading = HEADING.exec(line);
  if (heading) return [{ type: "heading", level: Math.min(3, heading[1]?.length ?? 1) as 1 | 2 | 3, inline: parseInline(heading[2] ?? "") }];
  const item = ITEM.exec(line);
  if (item) return [{ type: "item", inline: parseInline(item[1] ?? "") }];
  return [{ type: "paragraph", inline: parseInline(line) }];
};

// One block per line, as the Swift page view drew them, and one code block per fence. A fence without its end runs to the end of the text.
export const parseMarkdown = (text: string): Block[] => {
  const blocks: Block[] = [];
  let code: string[] | undefined;
  for (const raw of text.split(/\r?\n/)) {
    if (FENCE.test(raw)) {
      if (code) blocks.push({ type: "code", text: code.join("\n") });
      code = code ? undefined : [];
    } else if (code) code.push(raw);
    else blocks.push(...lineBlock(raw));
  }
  if (code) blocks.push({ type: "code", text: code.join("\n") });
  return blocks;
};

const plainOf = (nodes: Inline[]): string => nodes.map((node) => (node.type === "text" || node.type === "code" ? node.text : plainOf(node.children))).join("");

// The plain text of the first block that is not code, as the preview of a body on a board card.
export const previewOf = (text: string) => {
  const block = parseMarkdown(text).find(({ type }) => type !== "code");
  return block && block.type !== "code" ? plainOf(block.inline) : "";
};
