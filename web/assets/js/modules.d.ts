// Modules esbuild resolves that have no types of their own.

declare module "phoenix_html"

declare module "phoenix-colocated/marskal" {
  import type {HooksOptions} from "phoenix_live_view"
  export const hooks: HooksOptions
}

declare module "phoenix-colocated/marskal/colocated.css"

declare module "@fontsource-variable/atkinson-hyperlegible-next/wght.css"
declare module "@fontsource-variable/atkinson-hyperlegible-next/wght-italic.css"

// esbuild replaces this at build time.
declare const process: {env: {NODE_ENV: string}}

// phoenix_live_reload, in development.
interface LiveReloader {
  enableServerLogs(): void
  disableServerLogs(): void
  openEditorAtCaller(target: EventTarget | null): void
  openEditorAtDef(target: EventTarget | null): void
}

interface WindowEventMap {
  "phx:live_reload:attached": CustomEvent<LiveReloader>
}

interface Window {
  liveSocket: import("phoenix_live_view").LiveSocket
  liveReloader: LiveReloader
}
