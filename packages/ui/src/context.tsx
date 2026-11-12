import type { ComponentChildren, ComponentType } from "preact";
import { createContext, render } from "preact";
import { useContext } from "preact/hooks";
import type { Snapshot } from "./bridge.ts";
import { usePluginState, type PluginState } from "./hooks.ts";

const PluginContext = createContext<PluginState | undefined>(undefined);

// Wraps the root of a plugin UI, so each control shares one connection to the host.
export const PluginProvider = ({ children }: { children: ComponentChildren }) => <PluginContext.Provider value={usePluginState()}>{children}</PluginContext.Provider>;

export const usePlugin = (): PluginState => {
  const state = useContext(PluginContext);
  if (!state) throw new Error("usePlugin needs PluginProvider around the root of the page.");
  return state;
};

// Inside `mount`, the page renders only after the first snapshot, so the snapshot is always there.
export const useSnapshot = (): Snapshot => {
  const { snapshot } = usePlugin();
  if (!snapshot) throw new Error("useSnapshot needs mount, which waits for the first snapshot.");
  return snapshot;
};

const Gate = ({ children }: { children: ComponentChildren }) => {
  const { snapshot, error } = usePlugin();
  if (snapshot) return <>{children}</>;
  return error ? <p class="rt-empty">{error}</p> : null;
};

// Renders the page on #root of the fixed shell, after the first snapshot.
export const mount = (App: ComponentType) => {
  const root = document.getElementById("root");
  if (!root) return;
  render(
    <PluginProvider>
      <Gate>
        <App />
      </Gate>
    </PluginProvider>,
    root,
  );
};
