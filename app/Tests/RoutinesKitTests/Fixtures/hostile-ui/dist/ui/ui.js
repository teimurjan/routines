// Each try reports `blocked: true` when the host stopped it. See specs/002-plugin-ui/research.md, section 11.
(async () => {
  const send = (message) => window.webkit.messageHandlers.routines.postMessage(message);
  const report = (name, blocked) => send({ type: "report", name, blocked });
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const fails = async (work) => {
    try {
      await work();
      return false;
    } catch {
      return true;
    }
  };
  const loads = (element, url) =>
    new Promise((resolve) => {
      element.onload = () => resolve(true);
      element.onerror = () => resolve(false);
      setTimeout(() => resolve(false), 2000);
      element.src = url;
      document.body.append(element);
    });

  await report("inline script", window.inlineRan !== true);
  await report("remote script", !(await loads(document.createElement("script"), "https://example.com/x.js")) && window.remoteRan !== true);
  await report("fetch", await fails(() => fetch("https://example.com/")));
  await report("file link", (await fails(() => fetch("file:///etc/hosts"))) && !(await loads(new Image(), "file:///System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns")));
  await report("other plugin", (await fails(() => fetch("routines-ui://ui-plugin/ui.js"))) && !(await loads(document.createElement("script"), "routines-ui://ui-plugin/ui.js")));
  const action = await send({ type: "perform", cardId: "h1", actionId: "delete-everything" });
  await report("unlisted action", action.ok === false);
  location.href = "https://example.com/";
  await wait(500);
  await report("navigation", location.protocol === "routines-ui:");
  await report("done", true);
})();
