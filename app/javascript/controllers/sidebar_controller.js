import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "marskal.sidebar.collapsedFolders"

// Mobile drawer + folder expand/collapse. Collapse state is remembered in
// localStorage; ancestors of the current page are always revealed.
export default class extends Controller {
  static targets = [ "menuButton" ]

  connect() {
    this.boundKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
    this.restoreFolders()
    this.revealCurrent()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    document.body.classList.remove("sidebar-open")
  }

  toggle() {
    this.setOpen(!this.element.classList.contains("is-sidebar-open"))
  }

  close() {
    this.setOpen(false)
  }

  closeOnNavigate(event) {
    if (event.target.closest("a")) this.close()
  }

  toggleFolder(event) {
    event.preventDefault()
    const node = event.currentTarget.closest("[data-sidebar-folder-id]")
    if (!node) return

    const expanded = node.dataset.expanded !== "true"
    this.setExpanded(node, expanded)
    this.persist(node.dataset.sidebarFolderId, !expanded)
  }

  onKeydown(event) {
    if (event.key !== "Escape") return
    if (document.body.classList.contains("inspector-open")) return
    this.close()
  }

  setOpen(open) {
    this.element.classList.toggle("is-sidebar-open", open)
    document.body.classList.toggle("sidebar-open", open)
    this.menuButtonTargets.forEach((button) => {
      button.setAttribute("aria-expanded", open ? "true" : "false")
    })
  }

  restoreFolders() {
    const collapsed = this.collapsedIds()
    this.element.querySelectorAll("[data-sidebar-folder-id]").forEach((node) => {
      if (collapsed.includes(node.dataset.sidebarFolderId)) {
        this.setExpanded(node, false)
      }
    })
  }

  revealCurrent() {
    const current = this.element.querySelector("[aria-current='page']")
    if (!current) return

    let node = current.closest("[data-sidebar-folder-id]")
    while (node) {
      this.setExpanded(node, true)
      const parentBranch = node.parentElement?.closest("[data-sidebar-folder-id]")
      node = parentBranch
    }
  }

  setExpanded(node, expanded) {
    node.dataset.expanded = expanded ? "true" : "false"
    const toggle = node.querySelector(":scope > .nav-tree__row .nav-tree__toggle")
    if (toggle) toggle.setAttribute("aria-expanded", expanded ? "true" : "false")
  }

  persist(folderId, collapsed) {
    const ids = new Set(this.collapsedIds())
    if (collapsed) {
      ids.add(folderId)
    } else {
      ids.delete(folderId)
    }
    localStorage.setItem(STORAGE_KEY, JSON.stringify([ ...ids ]))
  }

  collapsedIds() {
    try {
      const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]")
      return Array.isArray(raw) ? raw.map(String) : []
    } catch {
      return []
    }
  }
}
