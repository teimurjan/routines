# Contract: Memory

Memory holds your answers, the outcomes, facts and preferences, each linked to its step. Memory informs a node. It never grants a permission (FR-036).

## The memory node

The host runs it, not a plugin.

1. When a run or a transition call ends, the host adds the ids of its new steps to `memory/pending.json`.
2. If no memory call runs, the host takes up to 20 pending steps and starts one.
3. The input holds each step, the kind, the title and the data of its actionable, and the question and the answer. The input holds no `body` of more than 4,000 characters.
4. The command is `claude -p --model haiku --output-format json --json-schema <schema> --restricted --strict-mcp-config --tools ""`. The node has no tool.
5. The host checks the output and writes each entry. Then it removes the steps from the queue.
6. If the call fails, the steps stay in the queue, and the run log of the routine names the failure. A step that fails three times leaves the queue.

The prompt tells the node that the steps are data, and that it must not copy an instruction from them into an entry.

```json
{
  "entries": [
    { "step": "9.4", "type": "answer", "text": "Use the staging key for the payments repo.", "tags": ["payments", "staging"] }
  ]
}
```

The host refuses three kinds of entry. The first has a `step` that was not in the input. The second has a type outside `answer`, `outcome`, `fact` and `preference`. The third has text over 1,000 characters. The host sets `routine` to the owner at the time of the step.

## The search tool

`Routines --memory-mcp --routine <id>` is a stdio MCP server with JSON-RPC 2.0. It answers `initialize`, `tools/list` and `tools/call`. Its name is `routines-memory`, and it has one tool.

```json
{
  "name": "search",
  "description": "Search the memory of this routine. It returns the closest entries first.",
  "inputSchema": {
    "type": "object",
    "required": ["query"],
    "properties": {
      "query": { "type": "string" },
      "tags": { "type": "array", "items": { "type": "string" } },
      "limit": { "type": "integer", "minimum": 1, "maximum": 8 }
    }
  }
}
```

The result is a list of `{ type, text, tags, writtenAt }`, at most 8 entries and 4,000 characters. `MemorySearch` gives each entry a score: the number of query words in its text, plus 2 for each matching tag. Equal scores put the newer entry first. An entry with a score of 0 does not show.

The server opens `memory/entries.json` read-only for each call, so an edit in the app shows in the next search. It has no method that writes.

A node gets the tool with `runNode({ ..., memory: true })`. The SDK adds:

```text
--strict-mcp-config --mcp-config {"mcpServers":{"routines-memory":{"command":"<appCommand>","args":["--memory-mcp","--routine","<id>"]}}}
--allowedTools mcp__routines-memory__search
```

## The Memory view

The sidebar gets a Memory item. It lists the entries, newest first, with a search field and a filter by routine and type. You can edit the text and the tags of an entry, and you can delete an entry. Each entry links to its actionable and its step.
