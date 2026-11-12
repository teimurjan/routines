# Routines Constitution

Routines is a macOS app that runs scheduled jobs with AI agents on one Mac. A Swift host runs plugins written in JavaScript. Each plugin shows its work in a UI of its own, and the Inbox lists all work that needs you. Code and tests cite these rules by number.

## Core Principles

### R1. The host knows no routine

The Swift host has no code for one routine. It loads plugins, runs them on a schedule, gives them host APIs and shows their UIs. A routine that the host must know about is a defect in the plugin API.

Why: one plugin can then change, fail or go away without a change to the host. Check: if a source file under `app/Sources` names a plugin id, `HostIsGenericTests` fails.

### R2. Agents decide and code acts

A node is one agent run with a typed input and a typed output. The agent returns JSON. Plugin code rejects a bad result and does the outward actions. A node gets only the tools that its task needs.

Why: tests can cover each decision without an agent run, and an agent cannot act outside its task. Check: every `agent()` call in a plugin passes an output schema.

### R3. A plugin gets only what its manifest declares

`plugin.json` lists the commands that a plugin can run and the hosts that it can reach. It also lists the paths that the plugin can use and its browser access. The host refuses every other call and returns the reason as an error.

Why: a fault in one plugin cannot reach the files or the accounts of another. Check: `PermissionsTests`.

### R4. Errors are values

A host call returns `{ ok: true, value }` or `{ ok: false, error }`. Plugin code returns `Result` values and does not throw. The host catches a thrown error, logs it and marks the run as failed.

Why: one failed call cannot stop the other work of a run without a record. Check: the SDK types return `Result`, and `RuntimeTests` covers a thrown error.

### R5. State survives a crash

A plugin writes each record before the outward action that it records, or after it, by the rule that its spec names. A state file that does not parse stops the run and does not reset.

Why: a crash must not repeat a public post or forget earlier work. Check: the ledger tests of each plugin.

### R6. The host owns the control surface

Each plugin shows its items in its own UI, and the Inbox lists each item that needs you. A plugin UI reaches only the items, the page and the actions of its own plugin. The manifest lists each action of a plugin, with its target: one item or the plugin. An item carries no actions, and the app draws no action control of its own. Each press goes through one host gate. The host finds the action in the manifest and checks its target, its item and its text. For an action with `confirm: true`, the host asks you first in its own dialog. Notifications and Inbox rows open an item in its plugin UI.

Why: one place lists all work that needs you, and a page cannot call an unlisted action or skip the dialog. Check: `ActionLookupTests`, `PluginUIBridgeTests`, `NativeActionsGoneTests` and `PluginUIWebKitTests`.

### R7. Plain code over frameworks

The host uses only Apple frameworks. A plugin bundles its own dependencies. A new dependency needs a reason in `research.md`.

Why: fewer parts to audit and to update. Check: `Package.swift` has no package dependencies.

## Constraints

The host targets macOS 15 or later and Swift 6. Plugins are TypeScript, bundled to one JavaScript file each by Bun, and run in JavaScriptCore. Plugin logic has unit tests that run under `bun test`. The host has tests that run under `swift test`.

Text that a person reads follows plain English: short sentences, active voice and simple tenses.

## Development Workflow

A new feature starts with `/speckit-specify` and gets its own folder `specs/NNN-name/`. Then run `/speckit-plan`, `/speckit-tasks` and `/speckit-implement`. A fix needs no spec, but a change to a contract updates the contract file in the same commit.

Before you finish a change, run `bun run check`. It runs the type check, the plugin tests, the plugin build and the host tests.

## Governance

This constitution overrides other practice. An amendment changes this file, names its reason and bumps the version. A minor version adds a rule. A major version removes or redefines one.

Version 2.0.0 redefined R6, because plugins can ship their own UI. See `specs/002-plugin-ui/`.

Version 3.0.0 redefines R6 again. The board and the card buttons are gone, each plugin shows only its UI, and the manifest is the only list of actions. See `specs/003-custom-ui-everywhere/`.

**Version**: 3.0.0 | **Ratified**: 2026-11-09 | **Last Amended**: 2026-11-09
