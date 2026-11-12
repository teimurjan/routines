import type { PageBlock } from "@routines/sdk";

type Props = Omit<Extract<PageBlock, { type: "status" }>, "type">;

// A colored dot, a label and an optional detail line, as the status block of a plugin page.
export const Status = ({ state, label, detail }: Props) => (
  <div class="rt-status" data-state={state}>
    <span class="rt-status__dot" aria-hidden="true" />
    <div class="rt-status__text">
      <strong class="rt-status__label">{label}</strong>
      {detail && <span class="rt-status__detail">{detail}</span>}
    </div>
  </div>
);
