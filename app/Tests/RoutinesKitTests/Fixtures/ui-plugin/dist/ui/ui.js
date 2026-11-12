// Lists the items of the snapshot as text, and lists them again on each snapshot event.
(async () => {
  const send = (message) => window.webkit.messageHandlers.routines.postMessage(message);
  const root = document.getElementById("root");
  const render = (snapshot) => {
    const list = document.createElement("ul");
    list.replaceChildren(...snapshot.items.map((item) => Object.assign(document.createElement("li"), { textContent: item.title })));
    root.replaceChildren(list);
  };
  window.addEventListener("routines", (event) => {
    if (event.detail.type === "snapshot") render(event.detail.value);
  });
  const first = await send({ type: "snapshot" });
  if (first.ok) render(first.value);
  await send({ type: "ready" });
})();
