# Research: Plugin UI in HTML and JavaScript

Each section names a decision, the reason for it and the other options. Code comments cite sections 3, 10 and 11 by number.

## 1. The surface that draws a plugin UI

Decision: one `WKWebView` per open UI tab. `RoutinesKit/UI/PluginWebView.swift` makes it, and `PluginUIView.swift` places it in SwiftUI with an `NSViewRepresentable`.

Rationale: WebKit is an Apple framework, so R7 holds. The page gets the system font, `prefers-color-scheme` and the text rendering of the app. The web view lives as long as its tab shows, so a hidden plugin costs no memory.

Alternatives considered: native layouts that the host draws from plugin data. They need a host change for each new shape. A JavaScriptCore context with a native view tree, which is a custom UI framework.

## 2. How the page loads its files

Decision: a `WKURLSchemeHandler` for the scheme `routines-ui`. `routines-ui://<plugin id>/<path>` maps to `<plugin dir>/dist/ui/<path>`. `routines-ui://<plugin id>/_image/<percent-encoded absolute path>` serves an image. If a stored card of the same plugin lists the exact path in `images`, the handler serves that image. Otherwise it refuses.

Rationale: `loadFileURL(_:allowingReadAccessTo:)` gives read access to a whole folder and uses `file:` origins, which are hard to limit. A custom scheme gives each plugin its own origin and lets the host set the response headers. The path rules are pure functions in `PluginUIResources.swift`. Tests cover `..`, symlinks out of the folder, encoded separators and unlisted images.

Alternatives considered: a local HTTP server, which opens a port that each process on the Mac can reach. A data URL per image, which makes each snapshot large.

## 3. How the host blocks foreign code and the network

Decision: four layers.

1. The scheme handler serves only the files of section 2. Each response carries this content policy: `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-src 'none'`. Inline script and remote files do not run.
2. A `WKContentRuleList` blocks each load whose URL does not start with `routines-ui://`. It also covers loads that the content policy does not name.
3. The navigation guard allows only the first load of `routines-ui://<plugin id>/index.html` in the main frame. It cancels every later load. The UI delegate returns nil for `window.open`. A link opens only through the bridge.
4. Each web view has its own `WKWebsiteDataStore.nonPersistent()` store, so pages share no storage. The store goes away with the web view.

The web view also accepts a bridge message only from its main frame with the origin `routines-ui://<plugin id>`.

Rationale: one layer can fail through a WebKit bug or a missed header. Each layer is a few lines, and the hostile page test of section 11 covers them together.

Alternatives considered: the content policy alone. It does not stop a load of a remote page in the main frame.

## 4. The bridge between the page and the host

Decision: the page sends messages with `window.webkit.messageHandlers.routines.postMessage(message)`, through a `WKScriptMessageHandlerWithReply`. The promise resolves with `{ ok: true, value }` or `{ ok: false, error }`. The host sends events with `callAsyncJavaScript`. It passes the event as an argument, not as text in the script. The page gets each event as a `routines` event on `window`. The messages are in [contracts/plugin-ui.md](contracts/plugin-ui.md).

Rationale: the reply handler gives each call a promise, so the page code reads like the plugin SDK. An argument of `callAsyncJavaScript` reaches the page as a value, so no text from an item can break out of a string literal.

Alternatives considered: `evaluateJavaScript` with JSON in the script text, which needs careful escaping. A polling loop, which wastes time and delays changes.

`PluginUIBridge.swift` decodes each message and returns a decision. It knows the plugin id of its web view, so a page cannot name another plugin. Tests cover each decision without WebKit.

## 5. Actions, the host check and the dialog

Decision: the manifest lists each action, with `target: "item"` for an item action. `ActionLookup` finds an action by its id in the manifest. It refuses an unknown id, a wrong target, an item that the plugin does not have and a text action without text. The bridge turns an action with `confirm: true` into a `confirm` decision. `ActionGate` in the app target is the one entry point for a press. For a `confirm` decision, it shows a native dialog and calls the host only after you press the action button. The dialog text is the action label and the stored card title, or the plugin name for a plugin action. Return presses the action button, and Escape presses Cancel.

Rationale: the page is not trusted, so the host looks up each action itself. The dialog is UI, so it lives in the app target. One gate for all presses makes it hard to skip. If other app code calls an action, `NativeActionsGoneTests` fails.

External actions from `Routines --perform` skip the gate. `permissions.external` allows them, and nobody is at the Mac to answer a dialog.

Alternatives considered: a dialog inside the page. A hijacked page can skip it, so it does not meet FR-008.

## 6. A background with no flash

Decision: three parts. The SwiftUI view behind the web view has the canvas color. The web view stays hidden until the page sends `ready`, or until 1 second passes. Then it shows the page or an error. The CSS of `@routines/ui` sets `color-scheme: light dark` and `html, body { background: var(--canvas) }`, with the dark values under `@media (prefers-color-scheme: dark)`. The web view also sets `underPageBackgroundColor` to the canvas color, for the area past the edge of a scroll.

Rationale: a web view paints white before its first frame, so it stays hidden until then. A web view follows the appearance of its window, so `prefers-color-scheme` changes at once. The accent color of the Mac has no exact CSS value. The snapshot carries it as a hex value, and `@routines/ui` sets `--accent` on the root element. The app reads the accent again after `NSColor.systemColorsDidChangeNotification`, and the next snapshot carries it.

Alternatives considered: a transparent web view through the private `drawsBackground` key, which is not public API. The CSS system color `AccentColor` alone, which WebKit does not match to the Mac accent in each place. `base.css` keeps it only as the value before the first snapshot.

## 7. The token source and the generated outputs

Decision: `design/tokens.json` holds each token. `scripts/build-tokens.ts` writes `app/Sources/Routines/Views/Tokens.swift` and `packages/ui/src/tokens.css`. Both outputs are in git, with a header that names the script. `bun run tokens` writes them. If an output differs from the source, `bun run tokens --check` fails. `bun run check` runs it. The format is in [contracts/tokens.md](contracts/tokens.md).

Rationale: a generated Swift enum gives a compile error for a missing token. Generated files in git keep `swift build` free of Bun. The `--check` flag stops a hand edit of a generated file.

Alternatives considered: the app reads the JSON at run time, which loses the compile error. An asset catalog for colors, which CSS cannot read.

`TokenUseTests.swift` scans `app/Sources/Routines/Views` outside `Tokens.swift` and `Theme.swift`. It fails on `Color(light:`, a hex color, `.system(size:` with a number and `cornerRadius:` with a number.

## 8. The UI library for plugin UIs

Decision: Preact 10 with JSX, in `packages/ui`, bundled into each plugin UI.

Rationale for the dependency (R7): Preact is small, has no dependencies of its own, and escapes each string in JSX. The only way to insert HTML is `dangerouslySetInnerHTML`. If a file in `packages/ui/src` contains it or `innerHTML`, `scripts/no-html.test.ts` fails. Hooks keep each plugin UI a set of small pure components. Bun builds JSX with `importSource: "preact"` and needs no plugin.

Alternatives considered: plain DOM code with `textContent`, which is safe but makes each plugin write its own update logic. React, which is larger and gives nothing more here. Lit, whose templates escape text too, but its classes do not fit the function style of the project.

Markdown: `parseMarkdown` in `markdown.ts` turns text into blocks and inline nodes, and the `Markdown` control draws them as elements. HTML in the text stays text. A link that is not `http` or `https` stays text, and a link opens through `openLink`.

## 9. Structured data on an item

Decision: a card has an optional `data` object. The host stores it and gives it only to the UI of the same plugin. The host does not draw it, and `activity.list` leaves it out. `BoardStore` refuses an upsert whose `data` is larger than 32 KB as JSON.

Rationale: a UI often needs fields, for example the priority and the owner of a ticket. Fields in `data` save the UI from parsing Markdown. The field is opaque to the host, so R1 holds.

Alternatives considered: a second store per plugin for UI data, which duplicates the board and its retention rules. Fields in the body, which make each UI parse Markdown.

The field `column` keeps its name and means the state of an item.

## 10. The build of a plugin UI

Decision: a plugin with `ui/main.tsx` gets a second bundle. `workspace/scripts/build-plugins.ts` removes `dist/ui` and builds the entry with `Bun.build`, `target: "browser"`, `format: "iife"` and the automatic JSX runtime of Preact. It writes `dist/ui/ui.js`, `dist/ui/ui.css` and each imported asset as `<name>-<hash>.<ext>`. A UI without CSS gets an empty `ui.css`. Then the script writes `dist/ui/index.html` from one fixed shell: a stylesheet link, a deferred script tag and an empty `#root` element.

Rationale: the host serves this shell, so a plugin cannot add inline script or a remote link to it. A classic script avoids the module rules of WebKit for custom schemes. The CSS that `main.tsx` imports, including the CSS of `@routines/ui`, ends in one file.

Alternatives considered: the HTML entry point of `Bun.build`, which writes module scripts and lets a plugin author edit the HTML.

## 11. Tests of the security rules

Decision: `PluginUITests.swift` covers the path rules, the image rule, the manifest and each bridge decision without WebKit. `PluginUIWebKitTests` loads the fixture `app/Tests/RoutinesKitTests/Fixtures/hostile-ui` in a real web view. Its page has inline script, a remote script, a remote image and an event attribute. Its script makes seven tries:

1. Inline script.
2. A remote script.
3. A `fetch` of a remote URL.
4. A `file:` load.
5. A file of another plugin.
6. An unlisted action.
7. A load of a remote page in the main frame.

If the host stopped a try, the try reports `blocked: true`. If each try reports `blocked: true`, the test passes. The test runs only with `ROUTINES_WEBKIT_TESTS=1`, because it needs a window server and a run loop.

Rationale: most rules are pure decisions, and a fast test covers them in `bun run check`. Only the content policy, the rule list and the navigation guard need WebKit.

## 12. The life of a web view

Decision: a web view lives while its tab shows. `PluginUIController` sends the first snapshot as the answer to `snapshot`. After `ready`, it sends each snapshot whose JSON differs from the last one that it sent. Each build of `plugin.js` or `ui.js` gives the UI view a new identity. A new build thus loads a new web view. When you open an item from the Inbox or a notification, the controller sends a `focus` event after `ready`.

Rationale: a new web view per open costs less than the 1 second goal, and no cache means no stale page.

## 13. The Inbox

Decision: the Inbox is a native list of the items of all plugins in `needs-you`, newest first, with a search field. A row shows the plugin mark, the title, the first body line, the status and the date. A row opens the plugin, and its UI gets the item through `focus`. The Inbox draws no action control.

Rationale: the Inbox mixes plugins, so no plugin UI can draw it. Each press of an action then comes from the UI of its own plugin.
