routines.definePlugin({
  onAction: async ({ cardId, actionId }) => ({ ok: true, value: `${actionId} ${cardId}` }),
  onPluginAction: async ({ actionId, text }) => ({ ok: true, value: `${actionId} ${text ?? ""}`.trim() }),
});
