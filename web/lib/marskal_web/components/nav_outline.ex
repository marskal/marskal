defmodule MarskalWeb.NavOutline do
  @moduledoc """
  Folders, projects, and tags as outlines: in the sidebar, on a folder's
  page, and on a tag's page (ADR 0009, ADR 0031).

  `scope/1` wraps the lists the keys move through. In the sidebar that is
  the whole sidebar, view links included; on a page, its outline alone.
  `list/1` is one outline, flat, with a depth on each row, as a task
  outline is. Its rows move by drag and drop and by the outline keys, and
  `MarskalWeb.NavMoves` makes the moves. A folder takes folders and
  projects, a tag takes tags, and a project takes nothing. Collapsed rows
  are kept per browser, the same in every outline.
  """

  use MarskalWeb, :html

  alias Marskal.Dates
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.ProjectNav
  alias Marskal.Projects.Project
  alias Marskal.Tags.Tree

  @doc """
  The rows below folder id `folder_id` (`nil` for the top), each folder
  followed by what it holds.
  """
  def project_rows(nav, folder_id, depth \\ 0) do
    nav
    |> ProjectNav.children(folder_id)
    |> Enum.flat_map(fn
      %ProjectFolder{} = folder ->
        below = project_rows(nav, folder.id, depth + 1)
        [row(:folder, folder.id, folder.name, depth, below != [], tone(folder)) | below]

      %Project{} = project ->
        [row(:project, project.id, project.title, depth, false, tone(project))]
    end)
  end

  @doc """
  The rows below tag id `parent_id` (`nil` for the top) that `include?`
  keeps, each tag followed by its children.
  """
  def tag_rows(%Tree{} = tree, parent_id, include?, depth \\ 0) do
    tree
    |> Tree.children(parent_id)
    |> Enum.filter(include?)
    |> Enum.flat_map(fn tag ->
      below = tag_rows(tree, tag.id, include?, depth + 1)
      [row(:tag, tag.id, tag.name, depth, below != [], tone(tag)) | below]
    end)
  end

  # Folders, projects, and tags alike; only a project can be deferred.
  defp tone(%{state: state}) when state in [:done, :dropped], do: state

  defp tone(%Project{} = project) do
    if Dates.deferred?(project, DateTime.utc_now()), do: :deferred
  end

  defp tone(_record), do: nil

  defp row(type, id, label, depth, children?, tone) do
    %{type: type, id: id, label: label, depth: depth, children?: children?, tone: tone}
  end

  attr :id, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @doc "What the keys move through, and the hook that runs the outlines inside it."
  def scope(assigns) do
    ~H"""
    <div id={@id} class={@class} phx-hook=".NavOutline" data-nav-scope {@rest}>
      {render_slot(@inner_block)}
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".NavOutline" extension="ts">
      import {ViewHook} from "phoenix_live_view"
      import Sortable from "sortablejs"

      // Collapsed folders and tags are kept per browser and never reach the
      // server. The saved set holds "folder:<id>" and "tag:<id>".
      const key = "marskal:nav:collapsed"

      function load(): Set<string> {
        try {
          const ids: unknown = JSON.parse(localStorage.getItem(key) ?? "[]")
          return new Set(Array.isArray(ids) ? ids.filter((id) => typeof id === "string") : [])
        } catch {
          return new Set()
        }
      }

      function save(ids: Set<string>) {
        try {
          localStorage.setItem(key, JSON.stringify([...ids]))
        } catch {
          // Private windows may refuse storage; the toggles still work.
        }
      }

      // The task list's keys (ADR 0031), as far as they fit here. Enter is
      // the link's own.
      type Prefix = "g"
      type Action =
        | "move-prev"
        | "move-next"
        | "move-first"
        | "move-last"
        | "collapse"
        | "expand"
        | "indent"
        | "outdent"
        | "sibling-up"
        | "sibling-down"

      const shared: Record<string, Action> = {
        ArrowUp: "move-prev",
        ArrowDown: "move-next",
        Home: "move-first",
        End: "move-last",
        ArrowLeft: "collapse",
        ArrowRight: "expand",
      }

      const vim: Record<string, Action> = {
        k: "move-prev",
        j: "move-next",
        G: "move-last",
        h: "collapse",
        l: "expand",
        ">": "indent",
        "<": "outdent",
        L: "indent",
        H: "outdent",
        K: "sibling-up",
        J: "sibling-down",
      }

      const events: Partial<Record<Action, string>> = {
        indent: "nav-indent",
        outdent: "nav-outdent",
        "sibling-up": "nav-up",
        "sibling-down": "nav-down",
      }

      const command = (event: KeyboardEvent) => event.metaKey || event.ctrlKey

      function binding(event: KeyboardEvent): Action | Prefix | null {
        const cmd = command(event)
        if (event.key === "Tab" && !cmd && !event.altKey) return event.shiftKey ? "outdent" : "indent"
        if (cmd && !event.altKey && event.key === "]") return "indent"
        if (cmd && !event.altKey && event.key === "[") return "outdent"
        if (event.altKey && !cmd && event.key === "ArrowUp") return "sibling-up"
        if (event.altKey && !cmd && event.key === "ArrowDown") return "sibling-down"
        if (cmd || event.altKey) return null
        const action = shared[event.key]
        if (action) return action
        if (document.getElementById("app-shell")?.dataset.keymap !== "vim") return null
        if (event.key === "g") return "g"
        return vim[event.key] ?? null
      }

      type Row = {type: string; id: string; depth: number; container: boolean}
      type Place = {parent_id: string | null; after: Row | null}

      const depthOf = (el: HTMLElement) => Number(el.dataset.depth ?? 0)
      const rowOf = (el: HTMLElement): Row => ({
        type: el.dataset.type!,
        id: el.dataset.id!,
        depth: depthOf(el),
        container: el.hasAttribute("data-container"),
      })
      const keyOf = (row: {type: string; id: string}) => `${row.type}:${row.id}`

      // Where a row put at `index` of `rows`, at `depth`, lands: under the
      // nearest shallower row above it, after the nearest row above at the
      // same depth before that. The top is the list's own root.
      function placeAt(rows: Row[], index: number, depth: number, root: string | null): Place {
        let after: Row | null = null
        for (let i = index - 1; i >= 0; i--) {
          const row = rows[i]!
          if (row.depth < depth) return {parent_id: row.id, after}
          if (row.depth === depth && after === null) after = row
        }
        return {parent_id: root, after}
      }

      // The depth a drop can take: at most one below the row above, when
      // that row can hold others, and at least that of the row below, so
      // the row below keeps its parent.
      function clampDepth(rows: Row[], index: number, depth: number) {
        const above = rows[index - 1]
        const below = rows[index]
        const max = above ? above.depth + (above.container ? 1 : 0) : 0
        const min = below ? Math.min(below.depth, max) : 0
        return Math.max(min, Math.min(max, depth))
      }

      // Rows are indented this much per level; the CSS uses the same.
      const indentRem = 1.25

      // Sortable blocks the click after a drag, and clears that only when
      // the row passes another. A sideways drag, to indent, passes none,
      // so the user's next click would be lost. A click no one else sees
      // uses the block up: Sortable stops it on the way down if it is
      // still set, and the sink stops it otherwise.
      function releaseClick() {
        const sink = document.createElement("span")
        sink.hidden = true
        sink.addEventListener("click", (event) => event.stopPropagation())
        document.body.append(sink)
        sink.dispatchEvent(new MouseEvent("click", {bubbles: true}))
        sink.remove()
      }

      export default class extends ViewHook<HTMLElement> {
        collapsed = new Set<string>()
        focusKey: {list: string; key: string} | null = null
        prefix: Prefix | null = null
        prefixTimer = 0
        sortables = new Map<HTMLElement, Sortable>()
        drag: {
          list: HTMLElement
          el: HTMLElement
          next: Node | null
          style: string | null
          depth: number
          startX: number
          hidden: HTMLElement[]
          from: Place
        } | null = null
        pointerX = 0

        lists(): HTMLElement[] {
          return Array.from(this.el.querySelectorAll<HTMLElement>("ul.nav-outline"))
        }

        // Every link the keys stop at, in order, skipping collapsed rows.
        stops(): HTMLElement[] {
          return Array.from(this.el.querySelectorAll<HTMLElement>("[data-nav-stop]")).filter(
            (el) => !el.closest(".nav-row[hidden]"),
          )
        }

        // Collapsed rows hide what they hold. Through this.js(), so the
        // state outlives the server's patches.
        apply() {
          for (const list of this.lists()) {
            // The depth of the collapsed row whose contents are being
            // passed, if any.
            let under = Infinity
            for (const el of list.querySelectorAll<HTMLElement>(":scope > .nav-row")) {
              const depth = depthOf(el)
              if (depth <= under) under = Infinity
              const hidden = under !== Infinity
              if (el.hasAttribute("hidden") !== hidden) {
                if (hidden) this.js().setAttribute(el, "hidden", "")
                else this.js().removeAttribute(el, "hidden")
              }
              const toggle = el.querySelector<HTMLElement>(":scope > .nav-toggle")
              if (!toggle) continue
              const collapsed = this.collapsed.has(keyOf(rowOf(el)))
              if (collapsed && !hidden) under = depth
              const expanded = String(!collapsed)
              if (toggle.getAttribute("aria-expanded") !== expanded) {
                this.js().setAttribute(toggle, "aria-expanded", expanded)
              }
            }
          }
        }

        toggle(row: HTMLElement) {
          const key = keyOf(rowOf(row))
          if (!this.collapsed.delete(key)) this.collapsed.add(key)
          save(this.collapsed)
          this.apply()
        }

        onClick = (event: MouseEvent) => {
          if (!(event.target instanceof Element)) return
          const toggle = event.target.closest(".nav-toggle")
          const row = toggle?.closest<HTMLElement>(".nav-row")
          if (row) this.toggle(row)
        }

        onPointerDown = (event: PointerEvent) => {
          this.pointerX = event.clientX
        }

        onPointerMove = (event: PointerEvent) => {
          this.pointerX = event.clientX
          if (this.drag) this.project()
        }

        // The rows as they stand mid-drag, without the dragged one and what
        // it carries, and where the dragged one sits among them.
        rowsNow(): {rows: Row[]; index: number} {
          const drag = this.drag!
          const rows: Row[] = []
          let index = 0
          for (const el of drag.list.querySelectorAll<HTMLElement>(":scope > .nav-row")) {
            if (el === drag.el) index = rows.length
            else if (!el.classList.contains("is-drag-hidden") && !el.hasAttribute("hidden")) rows.push(rowOf(el))
          }
          return {rows, index}
        }

        root(list: HTMLElement): string | null {
          return list.dataset.rootId || null
        }

        project(): Place {
          const drag = this.drag!
          const indent = parseFloat(getComputedStyle(document.documentElement).fontSize) * indentRem
          const {rows, index} = this.rowsNow()
          const wanted = drag.depth + Math.round((this.pointerX - drag.startX) / indent)
          const depth = clampDepth(rows, index, wanted)
          drag.el.style.setProperty("--depth", String(depth))
          return placeAt(rows, index, depth, this.root(drag.list))
        }

        startDrag(list: HTMLElement, el: HTMLElement) {
          const depth = depthOf(el)
          const hidden: HTMLElement[] = []
          for (let next = el.nextElementSibling; next instanceof HTMLElement; next = next.nextElementSibling) {
            if (!next.classList.contains("nav-row") || depthOf(next) <= depth) break
            next.classList.add("is-drag-hidden")
            hidden.push(next)
          }
          this.drag = {list, el, next: el.nextSibling, style: el.getAttribute("style"), depth, startX: this.pointerX, hidden, from: {parent_id: null, after: null}}
          const {rows, index} = this.rowsNow()
          this.drag.from = placeAt(rows, index, depth, this.root(list))
        }

        // The server re-renders the list in its new order, so the DOM goes
        // back as it was first; a refused move then leaves nothing stale.
        endDrag() {
          const drag = this.drag
          if (!drag) return
          const place = this.project()
          drag.list.insertBefore(drag.el, drag.next)
          if (drag.style === null) drag.el.removeAttribute("style")
          else drag.el.setAttribute("style", drag.style)
          for (const el of drag.hidden) el.classList.remove("is-drag-hidden")
          this.drag = null
          this.swallowClick()

          const same = (a: Row | null, b: Row | null) => a?.id === b?.id
          if (place.parent_id === drag.from.parent_id && same(place.after, drag.from.after)) return
          const row = rowOf(drag.el)
          this.focusKey = {list: drag.list.id, key: keyOf(row)}
          this.pushEvent("nav-place", {
            type: row.type,
            id: row.id,
            parent_id: place.parent_id,
            after_type: place.after?.type ?? null,
            after_id: place.after?.id ?? null,
          })
        }

        // One Sortable per outline. A list can come and go with a patch,
        // as the first tag does.
        attach() {
          const lists = this.lists()
          for (const [list, sortable] of this.sortables) {
            if (!lists.includes(list)) {
              sortable.destroy()
              this.sortables.delete(list)
            }
          }
          for (const list of lists) {
            if (this.sortables.has(list)) continue
            // The fallback drag, rather than native drag and drop, reports
            // the pointer throughout and works the same on touch.
            // The whole row drags, but for its toggle. A press that moves
            // less than the tolerance is a click; on touch, a hold starts
            // the drag, so a swipe still scrolls.
            this.sortables.set(list, Sortable.create(list, {
              draggable: ".nav-row",
              filter: ".is-drag-hidden, .nav-toggle",
              preventOnFilter: false,
              fallbackTolerance: 4,
              delay: 250,
              delayOnTouchOnly: true,
              forceFallback: true,
              fallbackOnBody: true,
              animation: 120,
              ghostClass: "is-drag-ghost",
              onStart: (event) => this.startDrag(list, event.item),
              onEnd: () => this.endDrag(),
            }))
          }
        }

        // The click that ends a drag does not follow the row's link.
        // LiveView listens on window as the click bubbles, so this catches
        // it first, on the way down.
        clickAfterDrag = false

        swallowClick() {
          this.clickAfterDrag = true
          window.setTimeout(() => {
            this.clickAfterDrag = false
            releaseClick()
          }, 0)
        }

        onClickCapture = (event: MouseEvent) => {
          if (!this.clickAfterDrag) return
          this.clickAfterDrag = false
          event.preventDefault()
          event.stopPropagation()
        }

        clearPrefix() {
          window.clearTimeout(this.prefixTimer)
          this.prefix = null
        }

        // Left at the top of a page's outline goes to the sidebar, and
        // Right in the sidebar goes to the page's list, when there is
        // nothing to collapse or expand.
        across(name: Action, row: HTMLElement | null): boolean {
          if (name === "collapse" && !this.inSidebar() && (!row || depthOf(row) === 0)) {
            return focusSidebar()
          }
          if (name === "expand" && this.inSidebar()) {
            window.dispatchEvent(new CustomEvent("marskal:focus-list"))
            return true
          }
          return false
        }

        inSidebar(): boolean {
          return this.el.closest(".sidebar") !== null
        }

        run(name: Action, stop: HTMLElement): boolean {
          const row = stop.closest<HTMLElement>(".nav-row")

          if (name.startsWith("move-")) {
            const stops = this.stops()
            const index = stops.indexOf(stop)
            const next =
              name === "move-prev" ? stops[index - 1]
              : name === "move-next" ? stops[index + 1]
              : name === "move-first" ? stops[0]
              : stops[stops.length - 1]
            next?.focus()
            return true
          }

          if (name === "collapse" || name === "expand") {
            const toggle = row?.querySelector(":scope > .nav-toggle")
            const expanded = toggle?.getAttribute("aria-expanded") === "true"
            if (row && toggle && (name === "collapse") === expanded) {
              this.toggle(row)
              return true
            }
            return this.across(name, row)
          }

          const eventName = events[name]
          const list = row?.closest<HTMLElement>("ul.nav-outline")
          if (!eventName || !row || !list) return false
          const target = rowOf(row)
          this.focusKey = {list: list.id, key: keyOf(target)}
          this.pushEvent(eventName, {type: target.type, id: target.id})
          return true
        }

        onKeydown = (event: KeyboardEvent) => {
          if (document.querySelector("dialog[open]")) return
          if (!(event.target instanceof HTMLElement)) return
          const stop = event.target.closest<HTMLElement>("[data-nav-stop]")
          if (!stop || !this.el.contains(stop)) return

          let name = binding(event)
          const prefix = this.prefix
          if (prefix) {
            this.clearPrefix()
            if (name === prefix) name = "move-first"
          }
          if (name === "g") {
            this.prefix = name
            this.prefixTimer = window.setTimeout(() => this.clearPrefix(), 1000)
            event.preventDefault()
            return
          }
          if (!name) return
          // A view link is not in an outline: Tab leaves it as usual.
          const rearranges = name in events
          if (rearranges && !stop.closest(".nav-row")) return
          if (this.run(name, stop) || rearranges) event.preventDefault()
        }

        mounted() {
          this.collapsed = load()
          this.el.addEventListener("click", this.onClick)
          this.el.addEventListener("keydown", this.onKeydown)
          this.el.addEventListener("pointerdown", this.onPointerDown)
          document.addEventListener("pointermove", this.onPointerMove)
          document.addEventListener("click", this.onClickCapture, true)
          this.attach()
          this.apply()
        }

        // A move can re-create the row, so focus goes back to it by key.
        updated() {
          this.attach()
          this.apply()
          if (!this.focusKey) return
          const {list, key} = this.focusKey
          this.focusKey = null
          const [type, id] = key.split(":")
          const row = document.getElementById(list)?.querySelector<HTMLElement>(
            `:scope > .nav-row[data-type="${type}"][data-id="${CSS.escape(id ?? "")}"]`,
          )
          const link = row?.querySelector<HTMLElement>("[data-nav-stop]")
          if (link && document.activeElement !== link) link.focus()
        }

        destroyed() {
          this.clearPrefix()
          this.el.removeEventListener("click", this.onClick)
          this.el.removeEventListener("keydown", this.onKeydown)
          this.el.removeEventListener("pointerdown", this.onPointerDown)
          document.removeEventListener("pointermove", this.onPointerMove)
          document.removeEventListener("click", this.onClickCapture, true)
          for (const sortable of this.sortables.values()) sortable.destroy()
          this.sortables.clear()
        }
      }

      // The sidebar's current row, else its first. Not while it is a closed
      // drawer.
      function focusSidebar(): boolean {
        const sidebar = document.getElementById("sidebar")
        if (!sidebar || sidebar.hasAttribute("inert") || sidebar.offsetParent === null) return false
        const stops = Array.from(sidebar.querySelectorAll<HTMLElement>("[data-nav-stop]"))
          .filter((el) => !el.closest(".nav-row[hidden]"))
        const target = stops.find((el) => el.classList.contains("is-current")) ?? stops[0]
        target?.focus()
        return Boolean(target)
      }

      // The task outline's Left at the top goes here too.
      window.addEventListener("marskal:focus-sidebar", () => focusSidebar())
    </script>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :root_id, :string, default: nil, doc: "the folder or tag the top rows are in"
  attr :current_id, :string, default: nil
  attr :inspector, :any, default: nil
  attr :class, :any, default: nil
  attr :label, :string, default: nil

  @doc "One outline of folders and projects, or of tags."
  def list(assigns) do
    ~H"""
    <ul
      id={@id}
      class={["nav-outline", @class]}
      data-root-id={@root_id}
      aria-label={@label}
    >
      <li
        :for={row <- @rows}
        id={"#{@id}-#{row.type}-#{row.id}"}
        class={["nav-row", row.tone && "is-#{row.tone}"]}
        style={row.depth > 0 && "--depth: #{row.depth}"}
        data-type={row.type}
        data-id={row.id}
        data-depth={row.depth}
        data-container={row.type != :project}
      >
        <button
          :if={row.children?}
          type="button"
          class="nav-toggle"
          aria-expanded="true"
          aria-label={gettext("Contents of %{name}", name: row.label)}
        >
          <Lucideicons.chevron_right class="icon" />
        </button>
        <MarskalWeb.NavComponents.record_link
          type={row.type}
          id={row.id}
          current_id={@current_id}
          inspector={@inspector}
          nav_stop
        >
          <.row_icon type={row.type} tone={row.tone} />
          <span class="nav-label" title={row.label}>{row.label}</span>
        </MarskalWeb.NavComponents.record_link>
      </li>
    </ul>
    """
  end

  attr :type, :atom, required: true
  attr :tone, :atom, default: nil

  # A project's icon says its state, as a task's checkbox does.
  defp row_icon(%{type: :folder} = assigns), do: ~H|<Lucideicons.folder class="icon" />|
  defp row_icon(%{type: :tag} = assigns), do: ~H|<Lucideicons.tag class="icon" />|

  defp row_icon(%{tone: :done} = assigns),
    do: ~H|<Lucideicons.circle_check_big class="icon" />|

  defp row_icon(%{tone: :dropped} = assigns), do: ~H|<Lucideicons.circle_off class="icon" />|
  defp row_icon(%{tone: :deferred} = assigns), do: ~H|<Lucideicons.circle_dashed class="icon" />|
  defp row_icon(assigns), do: ~H|<Lucideicons.circle class="icon" />|
end
