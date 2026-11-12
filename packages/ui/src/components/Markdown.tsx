import { bridge } from "../bridge.ts";
import { parseMarkdown, type Block, type Inline } from "../markdown.ts";

const InlineView = ({ nodes }: { nodes: Inline[] }) => (
  <>
    {nodes.map((node, index) => {
      switch (node.type) {
        case "text":
          return node.text;
        case "strong":
          return (
            <strong key={index}>
              <InlineView nodes={node.children} />
            </strong>
          );
        case "emphasis":
          return (
            <em key={index}>
              <InlineView nodes={node.children} />
            </em>
          );
        case "code":
          return <code key={index}>{node.text}</code>;
        case "link":
          return (
            <button type="button" class="rt-link" key={index} title={node.url} onClick={() => void bridge.openLink(node.url)}>
              <InlineView nodes={node.children} />
            </button>
          );
      }
    })}
  </>
);

const BlockView = ({ block }: { block: Block }) => {
  if (block.type === "code") return <pre class="rt-markdown__code">{block.text}</pre>;
  const content = <InlineView nodes={block.inline} />;
  if (block.type === "heading") {
    const Heading = (["h2", "h3", "h4"] as const)[block.level - 1] ?? "h4";
    return <Heading class={`rt-markdown__heading rt-markdown__heading--${block.level}`}>{content}</Heading>;
  }
  if (block.type === "item") return <li class="rt-markdown__item">{content}</li>;
  return <p class="rt-markdown__paragraph">{content}</p>;
};

// Draws the Markdown of a plugin as elements, never as HTML. A link opens in the default browser.
export const Markdown = ({ text }: { text: string }) => (
  <div class="rt-markdown">
    {parseMarkdown(text).map((block, index) => (
      <BlockView block={block} key={index} />
    ))}
  </div>
);
