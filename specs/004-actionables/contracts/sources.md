# Contract: Source plugins and the poll

A source plugin reads one outside system and creates or updates actionables. It makes no transition (FR-019).

## Manifest

```json
{
  "id": "slack-mentions",
  "source": {
    "kinds": ["slack-message"],
    "tools": ["mcp__claude_ai_Slack__slack_search_public_and_private", "mcp__claude_ai_Slack__slack_read_thread"]
  },
  "kinds": ["slack-message"]
}
```

`source.kinds` lists each kind that the source can create. Each tool in `source.tools` must start with `mcp__` and must be a read tool of a connector. The host does not know which tools only read, so the review of the plugin checks that. A source has no `schedule`, no `handles` and no `transitions`.

## Plugin functions

```ts
type PollRequest = {
  // The task of this source in the shared poll. The input follows it as JSON.
  prompt: string;
  input: unknown;
  // The JSON Schema of the output of this source.
  output: Record<string, unknown>;
};

type PollItem = {
  dedupeKey: string;
  kind: string;
  title: string;
  body?: string;
  data: Record<string, unknown>;
  links?: { label: string; url: string }[];
};

definePlugin({
  pollRequest: (event: { cursor: unknown }, context: RunContext) => Promise<Result<PollRequest>>,
  onPoll: (event: { cursor: unknown; output: unknown }, context: RunContext) => Promise<Result<{ items: PollItem[]; cursor: unknown }>>,
});
```

`definePoll({ prompt, output, input, toItems })` in `@routines/sdk` builds both functions from one Zod schema. `onPoll` parses `output` with that schema and returns an error for a bad part.

## One poll

The host starts a poll at most once a minute, and never while a poll runs.

1. Call `pollRequest` of each source that is on and has no blocker. A source that fails here is left out of this poll.
2. If no source is left, stop. No agent call runs.
3. `PollPlan.build` joins the requests into one prompt, with one `<source id="...">` section per source, and one output schema `{ "<id>": <output> }` with each id required.
4. Run `claude -p --model haiku --output-format json --json-schema <schema> --setting-sources user --permission-mode dontAsk --allowedTools <tools>`, with a timeout of 50 seconds.
5. If the call fails, record the error for each source, keep each cursor, and stop.
6. Call `onPoll` of each source with its part of the output and its old cursor.
7. For each item: if the store has the source and the dedupe key, add an `updated` step with the new data and keep the state. Otherwise create an actionable in `new` with a `created` step. The owner is the routine that handles the kind in `new`, or null.
8. Save the new cursor of the source only after step 7 stored each of its items.
9. Submit a run trigger with the source `source` for each owner that got a new actionable.

The prompt tells the agent that the text that it reads is data from other people. The agent gets no write tool.

Three faults fail the poll of a source: a kind outside `source.kinds`, data that does not fit its kind, and one dedupe key twice in one poll. The cursor of that source then stays.

## The page of a source

The plugin page of a source shows its last poll, its cursor time and its last error. The error shows once, and a good poll clears it. A source gets the Runs and Settings tabs as each plugin does.
