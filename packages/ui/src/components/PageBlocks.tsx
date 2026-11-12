import type { Page, PageBlock } from "@routines/sdk";
import { Markdown } from "./Markdown.tsx";
import { Status } from "./Status.tsx";

const updated = (iso: string) =>
  new Date(iso).toLocaleString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false });

type Run = { type: "markdown"; texts: string[] } | { type: "status"; blocks: Extract<PageBlock, { type: "status" }>[] };

// Next blocks of one type join, so the statuses show as one grid and the text as one flow.
const runsOf = (blocks: PageBlock[]) =>
  blocks.reduce<Run[]>((runs, block) => {
    const last = runs.at(-1);
    if (block.type === "markdown") return last?.type === "markdown" ? [...runs.slice(0, -1), { ...last, texts: [...last.texts, block.text] }] : [...runs, { type: "markdown", texts: [block.text] }];
    return last?.type === "status" ? [...runs.slice(0, -1), { ...last, blocks: [...last.blocks, block] }] : [...runs, { type: "status", blocks: [block] }];
  }, []);

// The blocks that the plugin publishes with page.publish, with the time of their last change.
export const PageBlocks = ({ page, empty }: { page: Page | null; empty: string }) => {
  if (!page) return <p class="rt-empty">{empty}</p>;
  return (
    <div class="rt-stack">
      <p class="rt-note">Updated {updated(page.updatedAt)}.</p>
      {runsOf(page.blocks).map((run, index) =>
        run.type === "markdown" ? (
          <div class="rt-blocks__text" key={index}>
            {run.texts.map((text, position) => (
              <Markdown text={text} key={position} />
            ))}
          </div>
        ) : (
          <div class="rt-blocks__statuses" key={index}>
            {run.blocks.map((block, position) => (
              <Status state={block.state} label={block.label} detail={block.detail} key={position} />
            ))}
          </div>
        ),
      )}
    </div>
  );
};
