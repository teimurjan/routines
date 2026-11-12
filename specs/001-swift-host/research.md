# Research: Swift host with JavaScript plugins

## Decision 1: JavaScriptCore as the plugin runtime

Decision: plugins run in JavaScriptCore, which is part of macOS.

Rationale: plugin authors write TypeScript and test it with Bun. JavaScriptCore adds no size to the app and starts a context in a few milliseconds. The host controls each API that a context has.

Alternatives: Swift plugins need a rebuild of the app for each change. A Bun process per plugin has Node APIs, so the host cannot limit what a plugin does.

## Decision 2: Web APIs in a prelude

Decision: `packages/prelude` gives each context `fetch`, timers, `URL`, `TextEncoder`, `atob`, `crypto` and `structuredClone` over host calls. `bun run build:prelude` bundles it into the resources of the host.

Rationale: JavaScriptCore has none of these APIs. `URL`, `URLSearchParams` and `structuredClone` come from core-js, because these parsers are large and must be exact. The other APIs are short and live in the prelude. Timers wait in the host, so a plugin waits without a busy loop.

## Decision 3: Results over one native function

Decision: each host call goes through `__native.call(method, json)` and returns the JSON of `{ ok, value }` or `{ ok, error }`.

Rationale: errors are values (R4). One native function with a method name keeps the Swift side small and easy to audit.

## Decision 4: A new context for each call

Decision: each run and each action gets a new context. The host loads the prelude and the bundle each time.

Rationale: a call cannot leak state into the next one. A hung promise holds only its own context. State that must last goes to files.

## Decision 5: A shared state folder

Decision: each plugin can use `~/.local/state/routines` without a permission. The data folder of the app is separate.

Rationale: plugins from different repos find shared state in one known place. A reinstall of the app, or a test run with `ROUTINES_DATA_DIR`, does not move the plugin state.

## Decision 6: WebKit for the browser

Decision: `permissions.browser` gives a plugin off-screen `WKWebView` pages.

Rationale: WebKit is part of macOS and runs pages as a real browser does. A page in an off-screen window runs its scripts and timers like a visible page. The plugin runs code in the page and gets JSON back.

Alternatives: a headless Chromium needs Node and a download of its own.

## Decision 7: Locks in memory

Decision: `LockService` is an actor in the host.

Rationale: all plugins run in one process, so a lock file and a process check are not necessary. At the end of a call, the host frees the locks of that call.

## Decision 8: Agents through the Claude Code CLI

Decision: `runAgent` runs `claude -p` through `exec`, with the Zod output schema as JSON Schema.

Rationale: the CLI brings the tools, the login and the claude.ai connectors. The output schema makes each node return typed JSON (R2). A `PreToolUse` hook limits a tool to the inputs that the code chose. The app binary is that hook, so the guard needs no Bun.

## Decision 9: Threads through the coding agent CLIs

Decision: a thread runs Claude Code in auto mode or Codex in its workspace-write sandbox, in a workspace that the app owns.

Rationale: both CLIs can resume a session and print JSON lines, so the app shows each step of a turn. The workspace holds the SDK, the docs and the build script, so the agent builds a plugin offline. After a change of the version file, the app replaces its own files. It never touches `plugins/`.

## Decision 10: External actions through a URL scheme

Decision: `Routines --perform` opens a `routines://perform` URL, and the running app writes the answer to a reply file.

Rationale: a second process cannot call into the running app without a server. A URL scheme needs no open port. The manifest list `permissions.external` and the replies folder limit what a URL can do.

## Decision 11: Dependencies

Decision: the host has no package dependencies. The SDK uses Zod, the UI controls use Preact, and the prelude uses core-js.

Rationale: Zod gives one schema for the agent output and its check. Preact is small. core-js gives parsers that follow the WHATWG standard.
