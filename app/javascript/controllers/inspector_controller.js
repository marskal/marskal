import { Controller } from "@hotwired/stimulus"

// Right-hand task inspector: desktop sidebar, slide-over on narrow screens.
export default class extends Controller {
  static targets = [ "panel", "empty" ]

  connect() {
    if (!this.frame) return

    this.enabled = true
    this.boundKeydown = this.onKeydown.bind(this)
    this.boundFrameLoad = this.onFrameLoad.bind(this)
    this.boundSubmitEnd = this.onSubmitEnd.bind(this)

    document.addEventListener("keydown", this.boundKeydown)
    this.element.addEventListener("turbo:submit-end", this.boundSubmitEnd)
    this.element.addEventListener("turbo:frame-load", this.boundFrameLoad)

    const selectedId = this.queryTaskId()
    if (selectedId) {
      this.setOpen(true)
      this.markSelected(selectedId)
    } else {
      this.setOpen(false)
    }
  }

  disconnect() {
    if (!this.enabled) return

    document.removeEventListener("keydown", this.boundKeydown)
    this.element.removeEventListener("turbo:submit-end", this.boundSubmitEnd)
    this.element.removeEventListener("turbo:frame-load", this.boundFrameLoad)
    document.body.classList.remove("inspector-open")
  }

  select(event) {
    const id = event.params.id
    this.markSelected(id)
    this.setOpen(true)
    this.setQuery(id)
  }

  selectRow(event) {
    if (event.target.closest("a, button, input, select, textarea, label")) return

    const link = event.currentTarget.querySelector("a.select")
    link?.click()
  }

  close() {
    this.setOpen(false)
    this.markSelected(null)
    this.setQuery(null)
    this.resetFrame()
  }

  onFrameLoad(event) {
    if (event.target.id !== "task_inspector") return

    const id = this.currentTaskId()
    if (!id) return

    this.markSelected(id)
    this.setOpen(true)
    this.setQuery(id)
  }

  onSubmitEnd() {
    const id = this.currentTaskId()
    if (id) this.markSelected(id)
  }

  onKeydown(event) {
    if (event.key !== "Escape") return
    if (!this.element.classList.contains("is-inspector-open")) return

    event.preventDefault()
    this.close()
  }

  setOpen(open) {
    const wasOpen = this.element.classList.contains("is-inspector-open")
    this.element.classList.toggle("is-inspector-open", open)
    document.body.classList.toggle("inspector-open", open)

    if (open) {
      this.element.classList.remove("is-sidebar-open")
      document.body.classList.remove("sidebar-open")
      if (!wasOpen && this.hasPanelTarget) {
        this.panelTarget.focus({ preventScroll: true })
      }
    }

    if (this.hasPanelTarget && window.matchMedia("(max-width: 64rem)").matches) {
      this.panelTarget.toggleAttribute("inert", !open)
    }
  }

  markSelected(id) {
    this.element.querySelectorAll(".task-row.is-selected").forEach((row) => {
      row.classList.remove("is-selected")
      row.removeAttribute("aria-current")
    })

    if (!id) return

    const row = this.element.querySelector(`.task-row[data-task-id="${CSS.escape(id)}"]`)
    if (!row) return

    row.classList.add("is-selected")
    row.setAttribute("aria-current", "true")
  }

  setQuery(id) {
    const url = new URL(window.location.href)
    if (id) {
      url.searchParams.set("task", id)
    } else {
      url.searchParams.delete("task")
    }
    window.history.replaceState(window.history.state, "", url)
  }

  queryTaskId() {
    return new URL(window.location.href).searchParams.get("task")
  }

  currentTaskId() {
    return this.frame?.querySelector(".task-inspector")?.dataset.taskId || null
  }

  resetFrame() {
    const frame = this.frame
    if (!frame) return

    frame.removeAttribute("src")
    if (this.hasEmptyTarget) {
      frame.innerHTML = this.emptyTarget.innerHTML
    }
  }

  get frame() {
    return this.element.querySelector("#task_inspector")
  }
}
