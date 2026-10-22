// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/marskal"
import "phoenix-colocated/marskal/colocated.css"
// The default typeface, self-hosted. --font in app.css names it.
import "@fontsource-variable/atkinson-hyperlegible-next/wght.css"
import "@fontsource-variable/atkinson-hyperlegible-next/wght-italic.css"
import topbar from "topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
// Read on every live mount, so a page reached by live navigation shows
// what this browser chose since the first load (MarskalWeb.Visibility).
function visibilityChoice(): string {
  const match = document.cookie.match(/(?:^|;\s*)marskal_visibility=([^;]*)/)
  return match ? match[1] : ""
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({_csrf_token: csrfToken, visibility: visibilityChoice()}),
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// A tab left open across a deploy keeps its old CSS and JS while the new
// server renders new markup. MarskalWeb.StaticChanged notices on reconnect.
// Such a tab reloads by itself a few seconds after it goes to the
// background, unless that would lose something: an open dialog, a change
// still on its way to the server, or text typed into a field that saves
// only when submitted. Forms marked data-autosave save as you type, so the
// wait lets their last edit land; LiveView does not refresh a textarea's
// default text, so their fields are not compared.
const settle = 5000
let updated = false
let pending: number | undefined

function unsaved(): boolean {
  if (document.querySelector("dialog[open], .phx-change-loading, .phx-submit-loading")) return true

  return Array.from(document.querySelectorAll("input, textarea, select")).some(field => {
    if (field.closest("[data-autosave]")) return false
    if (field instanceof HTMLSelectElement)
      return Array.from(field.options).some(option => option.selected !== option.defaultSelected)
    if (field instanceof HTMLInputElement && (field.type === "checkbox" || field.type === "radio"))
      return field.checked !== field.defaultChecked
    if (field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement)
      return field.value !== field.defaultValue
    return false
  })
}

function onVisibility() {
  if (document.hidden) {
    if (updated) scheduleReload()
  } else {
    // Back in view: never reload under the user's eyes.
    window.clearTimeout(pending)
  }
}

function scheduleReload() {
  window.clearTimeout(pending)
  pending = window.setTimeout(() => {
    if (document.hidden && !unsaved()) window.location.reload()
  }, settle)
}

window.addEventListener("phx:static-changed", () => {
  updated = true
  const banner = document.getElementById("app-updated")
  if (banner) banner.hidden = false
  onVisibility()
})
document.addEventListener("visibilitychange", onVisibility)
document.getElementById("app-updated-reload")?.addEventListener("click", () => window.location.reload())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown: string | null = null
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

