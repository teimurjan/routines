import { host, type PluginDefinition } from "./host.ts";

// Registers the plugin with the host. Call it once at the top level of the bundle.
export const definePlugin = (plugin: PluginDefinition) => host().definePlugin(plugin);
