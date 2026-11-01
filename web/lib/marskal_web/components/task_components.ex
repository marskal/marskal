defmodule MarskalWeb.TaskComponents do
  @moduledoc """
  The task list and its rows.
  """

  use MarskalWeb, :html

  attr :id, :string, required: true
  attr :tasks, :list, required: true
  attr :empty, :string, default: nil, doc: "a line to show when there are no tasks"
  attr :actions, :list, required: true
  attr :inspector, :any, default: nil

  attr :tags, :map,
    default: %{},
    doc: "effective tags by task id, from `Marskal.Tags.annotate/2`"

  attr :unavailable, :any, default: MapSet.new(), doc: "ids of tasks tag state blocks"
  attr :mark_inbox, :boolean, default: false, doc: "label tasks still in the inbox"

  attr :deferred, :any,
    default: MapSet.new(),
    doc: "ids of deferred tasks, from `Marskal.Tasks.deferred_ids/2`"

  attr :dates, :map,
    default: %{},
    doc: "effective dates by task id, from `Marskal.Tasks.effective_dates/2`"

  attr :resolved, :any,
    default: MapSet.new(),
    doc: "ids resolved along with a task or project above, from `Marskal.Tasks.resolved_ids/2`"

  attr :parents, :map,
    default: %{},
    doc: "each subtask's parent, for the breadcrumb in a flat list"

  attr :outline, :boolean,
    default: false,
    doc: "show the tasks as their outline: subtasks under their parent, in rank order"

  attr :nested, :boolean,
    default: false,
    doc:
      "subtasks under their parent, in rank order, while the top level keeps the list's " <>
        "order, newest first; rows collapse but do not move"

  attr :collapsed, :any, default: MapSet.new(), doc: "ids whose subtasks the outline hides"

  attr :zone, :string, default: "Europe/Copenhagen", doc: "the user's zone, for date labels"
  attr :repeating, :any, default: MapSet.new(), doc: "ids of tasks in a running series"
  attr :flagged, :any, default: MapSet.new(), doc: "ids of flagged tasks, own flag or project's"

  attr :new_row, :map,
    default: nil,
    doc: "the task being added inline on an outline, from `MarskalWeb.Outline`"

  attr :limit, :integer,
    default: nil,
    doc: "outline rows to render from the top; nil renders the whole list"

  slot :empty_state, doc: "shown instead of `empty` when there are no tasks"

  def list(assigns) do
    {shown, more?} = window(rows(assigns), assigns.limit)

    assigns =
      assign(assigns,
        now: DateTime.utc_now(),
        today: Marskal.Dates.today(assigns.zone),
        inherited_hint: "From the task or project above",
        rows: shown,
        more?: more?
      )

    # Rows keep a disclosure column only when some row can use it.
    assigns =
      assign(assigns,
        disclosures:
          (assigns.outline or assigns.nested) and Enum.any?(assigns.rows, & &1.children?)
      )

    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.task-row) {
        :scope {
          display: flex;
          flex-wrap: wrap;
          gap: 0.25rem 0.6rem;
          align-items: flex-start;
          justify-content: space-between;
          padding: 0.6rem 0.5rem;
          border-bottom: 1px solid var(--border);
          cursor: pointer;
        }

        :scope:hover {
          background: color-mix(in oklch, var(--text) 4%, transparent);
        }

        .check-form {
          flex: 0 0 auto;
          margin: 0;
        }

        .check {
          display: inline-grid;
          place-items: center;
          width: 2rem;
          height: 2rem;
          padding: 0;
          border: 0;
          border-radius: 6px;
          background: transparent;
          color: var(--text);
          cursor: pointer;
        }

        .check .icon {
          width: 1.5rem;
          height: 1.5rem;
        }

        .check__idle,
        .check__hint,
        .check__complete,
        .check__dropped {
          grid-area: 1 / 1;
          display: grid;
          place-items: center;
          transition: opacity 0.12s ease;
        }

        .check__hint {
          opacity: 0;
        }

        .check:is(:hover, :focus-visible) .check__idle {
          opacity: 0;
        }

        .check:is(:hover, :focus-visible) .check__hint {
          opacity: 0.4;
        }

        .check--done {
          color: var(--accent);
        }

        .check--dropped {
          color: var(--muted);
        }

        /* One highlight for the current row, however it was reached: a click
           selects it, and so do the keys (ADR 0031). Where the keys only
           move focus, the focused row takes the same tint. */
        :scope:is(.is-selected, :has(button.select:focus-visible)) {
          background: var(--accent-tint);
        }

        button.select {
          display: block;
          width: 100%;
          border: 0;
          background: transparent;
          padding: 0;
          color: inherit;
          font: inherit;
          text-align: left;
          cursor: pointer;
        }

        button.select:focus-visible {
          outline: none;
        }

        .check:focus-visible {
          outline: 2px solid var(--accent);
          outline-offset: 2px;
        }

        @media (max-width: 48rem) {
          .check {
            width: 2.75rem;
            height: 2.75rem;
            margin-block: -0.375rem;
            margin-inline-start: -0.375rem;
          }
        }

        .body {
          flex: 1 1 12rem;
          min-width: 0;
        }

        .title {
          min-width: 0;
        }

        .notes {
          display: -webkit-box;
          margin-top: 0.25rem;
          overflow: hidden;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          line-clamp: 2;
          color: var(--muted);
          font-size: 0.875rem;
        }

        .meta {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 0.3rem;
          margin-top: 0.3rem;
        }

        .meta:not(:has(*)) {
          display: none;
        }

        .meta .tag-chips {
          margin: 0;
        }

        .marks {
          display: inline-flex;
          flex-wrap: wrap;
          gap: 0.3rem;
          font-size: 0.8rem;
          color: var(--muted);
        }

        .mark {
          padding: 0 0.4rem;
          border: 1px solid var(--border);
          border-radius: 4px;
        }

        .mark--repeat {
          display: inline-flex;
          align-items: center;
          padding: 0;
          border: 0;
          color: var(--muted);
        }

        .mark--flag {
          display: inline-flex;
          align-items: center;
          padding: 0;
          border: 0;
          color: var(--flag);
        }

        .mark--overdue {
          border-color: currentColor;
          color: var(--danger);
        }

        .mark--today {
          border-color: currentColor;
          color: var(--accent);
        }

        .mark--inherited {
          border-style: dashed;
        }

        :scope[style*="--depth"] {
          margin-inline-start: calc(var(--depth) * 1.75rem);
        }

        .disclosure {
          flex: 0 0 1.5rem;
          align-self: center;
          margin-inline-end: -0.5rem;
        }

        .disclosure button {
          display: grid;
          place-items: center;
          width: 1.5rem;
          height: 1.5rem;
          padding: 0;
          border: 0;
          border-radius: 4px;
          background: transparent;
          color: var(--muted);
          cursor: pointer;
        }

        .disclosure .icon {
          width: 1rem;
          height: 1rem;
        }

        .disclosure button:focus-visible {
          outline: 2px solid var(--accent);
          outline-offset: 1px;
        }

        /* The whole row drags; a touch holds first, so the list still scrolls. */
        :scope:is([data-outline] > *) {
          -webkit-user-select: none;
          user-select: none;
        }

        :scope.is-drag-hidden {
          display: none;
        }

        :scope.is-drag-ghost {
          opacity: 0.4;
          border-style: dashed;
        }

        .crumb {
          color: var(--muted);
          font-size: 0.85em;
        }

        .crumb .chevron {
          margin-inline: 0.35em;
        }

        :scope.is-unavailable .title {
          color: var(--muted);
        }

        :scope.is-resolved .title {
          color: var(--muted);
        }

        :scope.is-resolved:has(.check--done) .title {
          text-decoration: line-through;
        }
      }

      .task-list {
        list-style: none;
        margin: 0;
        padding: 0;
      }

      .task-more {
        display: block;
        width: 100%;
        margin-top: 0.75rem;
        border-color: var(--border);
        background: transparent;
        color: var(--muted);
      }
    </style>
    <%= if @tasks == [] do %>
      {render_slot(@empty_state)}
      <p :if={@empty_state == [] and @empty} class="empty">{@empty}</p>
    <% end %>
    <ul
      id={@id}
      class="task-list"
      phx-hook=".Outline"
      data-outline={@outline}
      data-nested={@nested}
    >
      <%= for %{task: task, dates: d, depth: depth, children?: children?} <- @rows do %>
        <.new_row
          :if={new_row_at?(@new_row, task.id, :above)}
          anchor_id={task.id}
          depth={depth}
          outline={@outline}
          disclosures={@disclosures}
        />
        <li
          id={"task-#{task.id}"}
          class={[
            "task-row",
            MarskalWeb.Inspector.selected?(:task, task.id, @inspector) && "is-selected",
            (MapSet.member?(@unavailable, task.id) or MapSet.member?(@deferred, task.id)) &&
              "is-unavailable",
            (task.state != :to_do or MapSet.member?(@resolved, task.id)) && "is-resolved"
          ]}
          style={depth > 0 && "--depth: #{depth}"}
          data-depth={(@outline or @nested) && depth}
          data-inspect-type="task"
          data-inspect-id={task.id}
          aria-current={MarskalWeb.Inspector.selected?(:task, task.id, @inspector) && "true"}
          phx-click="inspect"
          phx-value-type="task"
          phx-value-id={task.id}
        >
          <span :if={@disclosures} class="disclosure">
            <button
              :if={children?}
              type="button"
              phx-click="outline-toggle"
              phx-value-id={task.id}
              aria-expanded={to_string(not MapSet.member?(@collapsed, task.id))}
              aria-label={
                if MapSet.member?(@collapsed, task.id), do: "Show subtasks", else: "Hide subtasks"
              }
            >
              <Lucideicons.chevron_right
                :if={MapSet.member?(@collapsed, task.id)}
                class="icon"
                aria-hidden="true"
              />
              <Lucideicons.chevron_down
                :if={not MapSet.member?(@collapsed, task.id)}
                class="icon"
                aria-hidden="true"
              />
            </button>
          </span>
          <span :if={:complete in @actions} class="check-form">
            <button
              type="button"
              class={check_class(task)}
              phx-click={check_event(task)}
              phx-value-id={task.id}
              title={check_label(task)}
              aria-label={check_label(task)}
            >
              <span :if={task.state == :dropped} class="check__dropped" aria-hidden="true">
                <Lucideicons.square_off class="icon" />
              </span>
              <span :if={task.state == :done} class="check__complete" aria-hidden="true">
                <Lucideicons.square_check_big class="icon" />
              </span>
              <span :if={task.state == :to_do} class="check__idle" aria-hidden="true">
                <Lucideicons.square class="icon" />
              </span>
              <span :if={task.state == :to_do} class="check__hint" aria-hidden="true">
                <Lucideicons.square_check_big class="icon" />
              </span>
            </button>
          </span>
          <div class="body">
            <button
              type="button"
              class="select title"
              phx-click="inspect"
              phx-value-type="task"
              phx-value-id={task.id}
            >
              <span :if={!(@outline or @nested) && @parents[task.id]} class="crumb">
                {@parents[task.id].title}<span class="chevron" aria-hidden="true">›</span>
              </span>
              {task.title}
            </button>
            <MarskalWeb.UrlLink.link url={task.url} />
            <div class="meta">
              <span
                :if={
                  (@mark_inbox and task.inbox) or d.planned_at != nil or d.due_at != nil or
                    MapSet.member?(@unavailable, task.id) or MapSet.member?(@deferred, task.id) or
                    MapSet.member?(@repeating, task.id) or
                    MapSet.member?(@flagged, task.id)
                }
                class="marks"
              >
                <span
                  :if={MapSet.member?(@flagged, task.id)}
                  class="mark mark--flag"
                  title={flag_label(task)}
                >
                  <Lucideicons.flag class="icon" aria-label={flag_label(task)} />
                </span>
                <span
                  :if={MapSet.member?(@repeating, task.id)}
                  class="mark mark--repeat"
                  title="Repeats"
                >
                  <Lucideicons.repeat class="icon" aria-label="Repeats" />
                </span>
                <span :if={@mark_inbox and task.inbox} class="mark mark--inbox">Inbox</span>
                <span :if={MapSet.member?(@unavailable, task.id)} class="mark mark--unavailable">
                  Unavailable
                </span>
                <span :if={MapSet.member?(@deferred, task.id)} class="mark mark--deferred">
                  {deferred_label(d, @zone, @today, @now)}
                </span>
                <span
                  :if={d.planned_at}
                  class={[
                    "mark mark--planned",
                    planned_today?(task, d, @zone, @today) && "mark--today",
                    inherited?(task, d, :planned_at) && "mark--inherited"
                  ]}
                  title={inherited?(task, d, :planned_at) && @inherited_hint}
                >
                  Planned {MarskalWeb.DateFields.short(d.planned_at, :planned_at, @zone, @today)}
                </span>
                <span
                  :if={d.due_at}
                  class={[
                    "mark mark--due",
                    Marskal.Dates.overdue?(%{state: task.state, due_at: d.due_at}, @now) &&
                      "mark--overdue",
                    inherited?(task, d, :due_at) && "mark--inherited"
                  ]}
                  title={inherited?(task, d, :due_at) && @inherited_hint}
                >
                  Due {MarskalWeb.DateFields.short(d.due_at, :due_at, @zone, @today)}
                </span>
              </span>
              <MarskalWeb.TagComponents.chips entries={Map.get(@tags, task.id, [])} />
            </div>
            <MarskalWeb.FormattedNotes.block text={task.notes} />
          </div>
        </li>
        <.new_row
          :if={new_row_at?(@new_row, task.id, :below)}
          anchor_id={task.id}
          depth={depth + if(@new_row.child?, do: 1, else: 0)}
          outline={@outline}
          disclosures={@disclosures}
        />
      <% end %>
    </ul>
    <button :if={@more?} id={"#{@id}-more"} type="button" class="task-more" phx-click="load-more">
      {gettext("Show more")}
    </button>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Outline" extension="ts">
      import {ViewHook} from "phoenix_live_view"
      import Sortable from "sortablejs"

      // Collapsed tasks are kept per browser. The server renders the
      // outline, so it is told the saved set on mount and tells the hook
      // what to save after each toggle.
      const key = "marskal:outline:collapsed"

      function load(): string[] {
        try {
          const ids: unknown = JSON.parse(localStorage.getItem(key) ?? "[]")
          return Array.isArray(ids) ? ids.filter((id) => typeof id === "string") : []
        } catch {
          return []
        }
      }

      function save(ids: string[]) {
        try {
          localStorage.setItem(key, JSON.stringify(ids))
        } catch {
          // Private windows may refuse storage; the outline still works.
        }
      }

      // List keys (ADR 0031). Both maps share the arrows, Space, Delete,
      // and the outline chords. Vim adds letters, and only while a row is
      // focused: a text field keeps what is typed. `gg` and `dd` are the
      // two-key sequences; another key after the first does its own action.
      type Map = "standard" | "vim"
      type Prefix = "g" | "d"
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
        | "check"
        | "drop"
        | "flag"
        | "new-below"
        | "new-above"
        | "open"

      const shared: Record<string, Action> = {
        ArrowUp: "move-prev",
        ArrowDown: "move-next",
        Home: "move-first",
        End: "move-last",
        ArrowLeft: "collapse",
        ArrowRight: "expand",
        " ": "check",
        Delete: "drop",
        Backspace: "drop",
        f: "flag",
        n: "new-below",
        Enter: "open",
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
        x: "check",
        o: "new-below",
        O: "new-above",
      }

      // What a completed sequence does.
      const sequences: Record<Prefix, Action> = {g: "move-first", d: "drop"}

      // The server event each row action sends. Movement and New stay here.
      const events: Partial<Record<Action, string>> = {
        collapse: "outline-toggle",
        expand: "outline-toggle",
        indent: "outline-indent",
        outdent: "outline-outdent",
        "sibling-up": "outline-up",
        "sibling-down": "outline-down",
        check: "task-check",
        drop: "task-drop",
        flag: "task-flag",
      }

      const outlineOnly: Action[] = ["indent", "outdent", "sibling-up", "sibling-down"]

      // Where the inspector is a pane beside the list, rather than a sheet
      // over it. Must match the `.Inspector` hook in layouts.ex.
      const narrow = window.matchMedia("(max-width: 64rem)")

      const command = (event: KeyboardEvent) => event.metaKey || event.ctrlKey

      function keymap(): Map {
        return document.getElementById("app-shell")?.dataset.keymap === "vim" ? "vim" : "standard"
      }

      function typing(event: KeyboardEvent): boolean {
        const target = event.target
        if (!(target instanceof HTMLElement)) return true
        return Boolean(
          target.closest("input, textarea, select, [contenteditable]:not([contenteditable='false'])"),
        )
      }

      function binding(event: KeyboardEvent, map: Map): Action | Prefix | null {
        const cmd = command(event)

        if (event.key === "Tab" && !cmd && !event.altKey) return event.shiftKey ? "outdent" : "indent"
        if (cmd && !event.altKey && event.key === "]") return "indent"
        if (cmd && !event.altKey && event.key === "[") return "outdent"
        if (event.altKey && !cmd && event.key === "ArrowUp") return "sibling-up"
        if (event.altKey && !cmd && event.key === "ArrowDown") return "sibling-down"
        if (cmd || event.altKey) return null

        const action = shared[event.key]
        if (action) return action
        if (map !== "vim") return null
        if (event.key === "g" || event.key === "d") return event.key
        return vim[event.key] ?? null
      }

      // The page's own task field wins, so a project task is not captured
      // into the inbox. Anywhere else, the inbox sheet opens, and its
      // title field takes focus.
      function focusNew() {
        const field = document.querySelector<HTMLElement>("[data-new-task] input[type='text']")
        if (field) {
          field.focus()
          return
        }
        const dialog = document.getElementById("quick-capture-sheet")
        if (!(dialog instanceof HTMLDialogElement)) return
        dialog.showModal()
        dialog.querySelector<HTMLElement>("input[type='text']")?.focus()
      }

      type Row = {id: string; depth: number}
      type Place = {parent_id: string | null; after_id: string | null}

      const depthOf = (el: HTMLElement) => Number(el.dataset.depth ?? 0)

      // Where a row put at `index` of `rows`, at `depth`, lands: under the
      // nearest shallower row above it, after the nearest row above at the
      // same depth before that.
      function placeAt(rows: Row[], index: number, depth: number): Place {
        let after: string | null = null
        for (let i = index - 1; i >= 0; i--) {
          const row = rows[i]!
          if (row.depth < depth) return {parent_id: row.id, after_id: after}
          if (row.depth === depth && after === null) after = row.id
        }
        return {parent_id: null, after_id: after}
      }

      // The depth a drop can take: at most one below the row above, and at
      // least that of the row below, so the row below keeps its parent.
      function clampDepth(rows: Row[], index: number, depth: number) {
        const above = rows[index - 1]
        const below = rows[index]
        const max = above ? above.depth + 1 : 0
        const min = below ? Math.min(below.depth, max) : 0
        return Math.max(min, Math.min(max, depth))
      }

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

      export default class extends ViewHook<HTMLUListElement> {
        focusId: string | null = null
        // A windowed list loads its next page when Show more scrolls into
        // view, and Down at the last row loads it and steps into it. End
        // stays put: a long list does not load the rest to jump to the end.
        loading = false
        afterLoad: (() => void) | null = null
        watched: HTMLButtonElement | null = null
        moreObserver = new IntersectionObserver((entries) => {
          if (entries.some((entry) => entry.isIntersecting)) this.loadMore()
        })
        prefix: Prefix | null = null
        prefixTimer = 0
        selectTimer = 0
        sortable: Sortable | null = null
        drag: {
          el: HTMLElement
          next: Node | null
          style: string | null
          depth: number
          startX: number
          hidden: HTMLElement[]
          from: Place
        } | null = null
        pointerX = 0

        onPointerDown = (event: PointerEvent) => {
          this.pointerX = event.clientX
        }

        onPointerMove = (event: PointerEvent) => {
          this.pointerX = event.clientX
          if (this.drag) this.project()
        }

        // The rows as they stand mid-drag, without the dragged one and the
        // subtree it carries, and where the dragged one sits among them.
        rowsNow(): {rows: Row[]; index: number} {
          const rows: Row[] = []
          let index = 0
          for (const el of this.el.querySelectorAll<HTMLElement>(":scope > .task-row")) {
            if (el === this.drag?.el) index = rows.length
            else if (!el.classList.contains("is-drag-hidden"))
              rows.push({id: el.dataset.inspectId!, depth: depthOf(el)})
          }
          return {rows, index}
        }

        // The depth the pointer asks for: one level per indent moved right
        // or left since the grab, within what the neighbors allow.
        project(): {place: Place; depth: number} {
          const drag = this.drag!
          const indent = parseFloat(getComputedStyle(document.documentElement).fontSize) * 1.75
          const {rows, index} = this.rowsNow()
          const wanted = drag.depth + Math.round((this.pointerX - drag.startX) / indent)
          const depth = clampDepth(rows, index, wanted)
          drag.el.style.setProperty("--depth", String(depth))
          return {place: placeAt(rows, index, depth), depth}
        }

        startDrag(el: HTMLElement) {
          const depth = depthOf(el)
          const hidden: HTMLElement[] = []
          for (let next = el.nextElementSibling; next instanceof HTMLElement; next = next.nextElementSibling) {
            if (!next.classList.contains("task-row") || depthOf(next) <= depth) break
            next.classList.add("is-drag-hidden")
            hidden.push(next)
          }
          this.drag = {el, next: el.nextSibling, style: el.getAttribute("style"), depth, startX: this.pointerX, hidden, from: {parent_id: null, after_id: null}}
          const {rows, index} = this.rowsNow()
          this.drag.from = placeAt(rows, index, depth)
        }

        // The server re-renders the list in its new order, so the DOM goes
        // back as it was first; a refused move then leaves nothing stale.
        endDrag() {
          const drag = this.drag
          if (!drag) return
          const {place} = this.project()
          this.el.insertBefore(drag.el, drag.next)
          if (drag.style === null) drag.el.removeAttribute("style")
          else drag.el.setAttribute("style", drag.style)
          for (const el of drag.hidden) el.classList.remove("is-drag-hidden")
          this.drag = null
          this.swallowClick()

          if (place.parent_id === drag.from.parent_id && place.after_id === drag.from.after_id) return
          this.focusId = drag.el.dataset.inspectId!
          this.pushEvent("outline-place", {id: this.focusId, ...place})
        }

        // The click that ends a drag neither opens the row nor follows a
        // link. LiveView listens on window as the click bubbles, so this
        // catches it first, on the way down.
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

        // Indent and reorder belong to an outline. Collapse only when the
        // row can change: Left closes an open row, Right opens a closed one.
        allowed(name: Action, row: HTMLElement): boolean {
          if (outlineOnly.includes(name) && !this.el.hasAttribute("data-outline")) return false
          if (name !== "collapse" && name !== "expand") return true
          const button = row.querySelector(".disclosure button")
          if (!button) return false
          const expanded = button.getAttribute("aria-expanded") === "true"
          return name === "collapse" ? expanded : !expanded
        }

        moreButton(): HTMLButtonElement | null {
          const button = document.getElementById(`${this.el.id}-more`)
          return button instanceof HTMLButtonElement ? button : null
        }

        // Watching afresh reports the button's state now, so a page that
        // leaves it in view loads the next one too.
        watchMore() {
          this.moreObserver.disconnect()
          this.watched = this.moreButton()
          if (this.watched) this.moreObserver.observe(this.watched)
        }

        loadMore(then?: () => void) {
          if (then) this.afterLoad = then
          if (this.loading) return
          this.loading = true
          this.pushEvent("load-more", {})
            .then(() => {
              const after = this.afterLoad
              this.afterLoad = null
              after?.()
            })
            .catch(() => {
              this.afterLoad = null
            })
            .finally(() => {
              this.loading = false
              this.watchMore()
            })
        }

        // The row after the given one, once the next page is in.
        stepFrom(id: string) {
          const rows = this.rows()
          const current = this.el.querySelector<HTMLElement>(`#task-${CSS.escape(id)}`)
          const target = current ? rows[rows.indexOf(current) + 1] : undefined
          if (!target) return
          target.querySelector<HTMLElement>("button.select")?.focus()
          this.select(target)
        }

        rows(): HTMLElement[] {
          return Array.from(this.el.querySelectorAll<HTMLElement>(":scope > .task-row"))
        }

        target(name: Action, row: HTMLElement): HTMLElement | undefined {
          const rows = this.rows()
          const index = rows.indexOf(row)
          if (name === "move-prev") return rows[index - 1]
          if (name === "move-next") return rows[index + 1]
          if (name === "move-first") return rows[0]
          if (name === "move-last") return rows[rows.length - 1]
          return undefined
        }

        // The focused row is the selected one, and the inspector pane shows
        // it. The highlight moves at once; the inspector follows when the
        // keys pause, and replaces the history entry rather than adding one.
        // Where the inspector is a sheet, the keys only move the highlight.
        select(row: HTMLElement) {
          if (narrow.matches) return
          for (const other of document.querySelectorAll(".task-row.is-selected")) {
            other.classList.remove("is-selected")
          }
          row.classList.add("is-selected")
          window.clearTimeout(this.selectTimer)
          const id = row.dataset.inspectId
          this.selectTimer = window.setTimeout(
            () => this.pushEvent("inspect", {type: "task", id, replace: true}),
            150,
          )
        }

        // Enter opens the row in the inspector and, beside the list, moves
        // focus there to edit. A sheet takes focus as it opens.
        open(id: string) {
          window.clearTimeout(this.selectTimer)
          this.pushEvent("inspect", {type: "task", id, replace: !narrow.matches})
          if (!narrow.matches) document.querySelector<HTMLElement>(".app-inspector")?.focus()
        }

        // A click selects the row, and focus stays on the list so the keys
        // go on from there.
        onClick = (event: MouseEvent) => {
          if (narrow.matches || !(event.target instanceof Element)) return
          if (event.target.closest("a, input, textarea, select, button:not(.select)")) return
          const row = event.target.closest<HTMLElement>(".task-row")
          if (!row || !this.el.contains(row)) return
          row.querySelector<HTMLElement>("button.select")?.focus({preventScroll: true})
        }

        run(name: Action, row: HTMLElement, id: string) {
          if (name.startsWith("move-")) {
            const next = this.target(name, row)
            if (next && next !== row) {
              next.querySelector<HTMLElement>("button.select")?.focus()
              this.select(next)
              return
            }
            if (name === "move-next" && this.moreButton()) this.loadMore(() => this.stepFrom(id))
            return
          }

          // On an outline, `n` (and `o`) and `O` add a task inline beside the
          // row. Other lists have no place for it, so they use the add field.
          if (name === "new-below" || name === "new-above") {
            if (!this.el.hasAttribute("data-outline")) focusNew()
            else this.pushEvent("inline-new", {id, where: name === "new-below" ? "below" : "above"})
            return
          }

          if (name === "open") {
            this.open(id)
            return
          }

          const eventName = events[name]
          if (!eventName) return
          this.focusId = id
          this.pushEvent(eventName, {id})
        }

        onKeydown = (event: KeyboardEvent) => {
          if (typing(event) || document.querySelector("dialog[open]")) return
          if (!(event.target instanceof HTMLElement)) return
          const row = event.target.closest<HTMLElement>(".task-row")
          if (!row || !this.el.contains(row)) return
          const id = row.dataset.inspectId
          if (!id) return

          let name = binding(event, keymap())
          const prefix = this.prefix
          if (prefix) {
            this.clearPrefix()
            if (name === prefix) name = sequences[prefix]
          }
          if (name === "g" || name === "d") {
            this.prefix = name
            this.prefixTimer = window.setTimeout(() => this.clearPrefix(), 1000)
            event.preventDefault()
            return
          }
          if (!name) return
          // Left at the top, with nothing to collapse, goes to the sidebar.
          if (name === "collapse" && depthOf(row) === 0 && !this.allowed(name, row)) {
            event.preventDefault()
            window.dispatchEvent(new CustomEvent("marskal:focus-sidebar"))
            return
          }
          if (!this.allowed(name, row)) return
          event.preventDefault()
          this.run(name, row, id)
        }

        mounted() {
          this.el.addEventListener("keydown", this.onKeydown)
          this.el.addEventListener("click", this.onClick)
          this.watchMore()
          // Back to a row when an inline new task closes.
          this.handleEvent("outline-focus", ({id}: {id: string}) => {
            const row = this.el.querySelector<HTMLElement>(`#task-${CSS.escape(id)}`)
            if (!row) return
            row.querySelector<HTMLElement>("button.select")?.focus()
            this.select(row)
          })
          const outline = this.el.hasAttribute("data-outline")
          const nested = this.el.hasAttribute("data-nested")
          if (!outline && !nested) return
          this.handleEvent("outline-collapsed", ({ids}: {ids: string[]}) => save(ids))
          const ids = load()
          if (ids.length) this.pushEvent("outline-collapsed", {ids})

          // A nested list only collapses; its rows do not move.
          if (!outline) return
          this.el.addEventListener("pointerdown", this.onPointerDown)
          document.addEventListener("pointermove", this.onPointerMove)
          document.addEventListener("click", this.onClickCapture, true)

          // The fallback drag, rather than native drag and drop, reports the
          // pointer throughout and works the same on touch.
          // The whole row drags, from anywhere but its controls. A press
          // that moves less than the tolerance is a click; on touch, a
          // hold starts the drag, so a swipe still scrolls.
          this.sortable = Sortable.create(this.el, {
            draggable: ".task-row",
            filter: ".is-drag-hidden, a, input, button:not(.select), .disclosure",
            preventOnFilter: false,
            fallbackTolerance: 4,
            delay: 250,
            delayOnTouchOnly: true,
            forceFallback: true,
            fallbackOnBody: true,
            animation: 120,
            ghostClass: "is-drag-ghost",
            onStart: (event) => this.startDrag(event.item),
            onEnd: () => this.endDrag(),
          })
        }

        // A move can re-create the row, so focus goes back to it by id.
        updated() {
          if (this.moreButton() !== this.watched) this.watchMore()
          if (!this.focusId) return
          const title = this.el.querySelector<HTMLElement>(`#task-${CSS.escape(this.focusId)} button.select`)
          if (title && document.activeElement !== title) title.focus()
          this.focusId = null
        }

        destroyed() {
          this.clearPrefix()
          window.clearTimeout(this.selectTimer)
          this.el.removeEventListener("keydown", this.onKeydown)
          this.el.removeEventListener("click", this.onClick)
          this.el.removeEventListener("pointerdown", this.onPointerDown)
          document.removeEventListener("pointermove", this.onPointerMove)
          document.removeEventListener("click", this.onClickCapture, true)
          this.sortable?.destroy()
          this.moreObserver.disconnect()
        }
      }
    </script>
    """
  end

  defp new_row_at?(%{anchor_id: id, where: :above}, id, :above), do: true
  defp new_row_at?(%{anchor_id: id, where: :below}, id, :below), do: true
  defp new_row_at?(_new_row, _id, _where), do: false

  attr :anchor_id, :string, required: true
  attr :depth, :integer, required: true
  attr :outline, :boolean, required: true
  attr :disclosures, :boolean, required: true

  # A task being added inline, by `o` and `O` (ADR 0031). Enter adds it and
  # opens the next below it; Escape, or leaving it empty, ends. The
  # inspector edits the same draft, so moving there does not end the row.
  defp new_row(assigns) do
    ~H"""
    <li id="task-new" class="task-new" style={@depth > 0 && "--depth: #{@depth}"}>
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.task-new) {
          :scope {
            display: flex;
            align-items: center;
            gap: 0.6rem;
            padding: 0.6rem 0.5rem;
            border-bottom: 1px solid var(--border);
          }

          :scope[style*="--depth"] {
            margin-inline-start: calc(var(--depth) * 1.75rem);
          }

          .disclosure-space {
            flex: 0 0 1.5rem;
            margin-inline-end: -0.5rem;
          }

          .check-space {
            display: inline-grid;
            flex: 0 0 2rem;
            place-items: center;
            height: 2rem;
            color: var(--muted);
          }

          .check-space .icon {
            width: 1.5rem;
            height: 1.5rem;
          }

          form {
            flex: 1 1 auto;
            margin: 0;
          }

          input[type="text"] {
            width: 100%;
            padding: 0;
            border: 0;
            border-radius: 0;
            background: transparent;
            color: inherit;
            font: inherit;
          }

          input[type="text"]:focus-visible {
            outline: none;
          }
        }
      </style>
      <span :if={@disclosures} class="disclosure-space" aria-hidden="true"></span>
      <span class="check-space" aria-hidden="true"><Lucideicons.square class="icon" /></span>
      <form
        id="task-new-form"
        phx-submit="inline-create"
        phx-change="inline-title"
        phx-hook=".NewTask"
      >
        <input
          id={"task-new-title-#{@anchor_id}"}
          type="text"
          name="title"
          autocomplete="off"
          enterkeyhint="next"
          placeholder={gettext("New task")}
          aria-label={gettext("New task")}
          phx-mounted={JS.focus()}
          phx-keydown="inline-cancel"
          phx-key="Escape"
        />
        <script :type={Phoenix.LiveView.ColocatedHook} name=".NewTask" extension="ts">
          import {ViewHook} from "phoenix_live_view"

          // Leaving the title saves the task. Focus moving to the inspector's
          // own title keeps it unsaved: that field is the same title. Enter
          // submits this form, so that blur must not save a second time.
          export default class extends ViewHook {
            mounted() {
              let skipBlur = false
              this.el.addEventListener("keydown", (event: KeyboardEvent) => {
                if (event.key === "Enter") skipBlur = true
              })
              this.el.addEventListener("focusout", () => {
                const skip = skipBlur
                skipBlur = false
                window.setTimeout(() => {
                  if (skip || !this.el.isConnected) return
                  const active = document.activeElement
                  if (active instanceof Element && active.closest("#task-new, #inspector-new-task-title")) return
                  const input = this.el.querySelector("input")
                  if (input instanceof HTMLInputElement) this.pushEvent("inline-blur", {value: input.value})
                }, 0)
              })
              this.handleEvent("inline-title", ({title}: {title: string}) => {
                const input = this.el.querySelector("input")
                if (input instanceof HTMLInputElement && document.activeElement !== input) input.value = title
              })
            }
          }
        </script>
      </form>
    </li>
    """
  end

  @doc """
  Where a task lives, from a form value: `"inbox"`, `"none"`, or a project
  id (ADR 0017).
  """
  def parse_location("inbox"), do: :inbox
  def parse_location(value) when value in ["none", ""], do: :none
  def parse_location(project_id) when is_binary(project_id), do: project_id

  # `limit` keeps the top of the outline. The cut stops before the next
  # row, unless that row is inside the subtree of the last one shown: an
  # expanded parent keeps the children that follow it. End does not ask
  # for the rows past the cut.
  defp window(rows, nil), do: {rows, false}

  defp window(rows, limit) when is_integer(limit) and limit >= 0 do
    {shown, rest} = Enum.split(rows, limit)

    case List.last(shown) do
      nil ->
        {shown, rest != []}

      last ->
        {subtree, rest} = Enum.split_while(rest, &(&1.depth > last.depth))
        {shown ++ subtree, rest != []}
    end
  end

  # One row per task shown, with the dates it goes by: its own, or those
  # inherited from the task or project above
  # (`Marskal.Tasks.effective_dates/2`). A flat list keeps the given order.
  # An outline puts each subtask under its parent, siblings by rank, and
  # skips what a collapsed task holds. A task whose parent is not in the
  # list starts at the top. A nested list keeps its top level as given.
  defp rows(%{outline: false, nested: false} = assigns),
    do: Enum.map(assigns.tasks, &row(&1, assigns.dates, 0, false))

  defp rows(assigns) do
    ids = MapSet.new(assigns.tasks, & &1.id)

    children =
      Enum.group_by(assigns.tasks, fn task ->
        if MapSet.member?(ids, task.parent_id), do: task.parent_id, else: :top
      end)

    walk(children, :top, 0, assigns)
  end

  defp walk(children, key, depth, assigns) do
    children
    |> Map.get(key, [])
    |> siblings(key == :top and assigns.nested)
    |> Enum.flat_map(fn task ->
      children? = Map.has_key?(children, task.id)

      below =
        if children? and not MapSet.member?(assigns.collapsed, task.id),
          do: walk(children, task.id, depth + 1, assigns),
          else: []

      [row(task, assigns.dates, depth, children?) | below]
    end)
  end

  defp siblings(tasks, true = _as_given), do: tasks
  defp siblings(tasks, _as_given), do: Enum.sort_by(tasks, &{&1.rank, &1.id})

  defp row(task, dates, depth, children?),
    do: %{task: task, dates: Map.get(dates, task.id, task), depth: depth, children?: children?}

  defp inherited?(task, dates, field),
    do: is_nil(Map.get(task, field)) and Map.get(dates, field) != nil

  # Defer comes from the task or anything above it; the latest one wins.
  defp deferred_label(dates, zone, today, now) do
    if Marskal.Dates.deferred?(dates, now) and not dates.deferred_indefinitely and
         dates.defer_until,
       do:
         "Deferred until #{MarskalWeb.DateFields.short(dates.defer_until, :defer_until, zone, today)}",
       else: "Deferred"
  end

  defp planned_today?(task, dates, zone, today) do
    task.state == :to_do and elem(Marskal.Dates.to_local(dates.planned_at, zone), 0) == today
  end

  defp flag_label(%{flagged: true}), do: "Flagged"
  defp flag_label(_task), do: "Flagged by its project"

  defp check_event(%{state: :to_do}), do: "complete"
  defp check_event(_task), do: "reopen"

  defp check_label(%{state: :to_do}), do: "Mark as done"
  defp check_label(_task), do: "Reopen"

  defp check_class(%{state: :done}), do: "check check--done"
  defp check_class(%{state: :dropped}), do: "check check--dropped"
  defp check_class(_task), do: "check"
end
