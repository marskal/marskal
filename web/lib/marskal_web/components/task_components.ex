defmodule MarskalWeb.TaskComponents do
  @moduledoc """
  The task list and its rows.
  """

  use MarskalWeb, :html

  attr :id, :string, required: true
  attr :tasks, :list, required: true
  attr :empty, :string, required: true
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

  def list(assigns) do
    assigns =
      assign(assigns,
        now: DateTime.utc_now(),
        today: Marskal.Dates.today(assigns.zone),
        inherited_hint: "From the task or project above",
        rows: rows(assigns)
      )

    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.task-row) {
        :scope {
          display: flex;
          flex-wrap: wrap;
          gap: 0.75rem 0.85rem;
          align-items: flex-start;
          justify-content: space-between;
          padding: 0.85rem 1rem;
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          cursor: pointer;
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

        :scope.is-selected {
          background: color-mix(in srgb, var(--accent) 16%, var(--surface));
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
          margin-top: 0.35rem;
          color: var(--muted);
          font-size: 0.9rem;
        }

        .marks {
          display: inline-flex;
          gap: 0.35rem;
          margin-inline-start: 0.5rem;
          font-size: 0.75rem;
          color: var(--muted);
          vertical-align: middle;
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

        .drag-handle {
          flex: 0 0 1rem;
          align-self: center;
          margin-inline: -0.5rem -0.6rem;
          color: var(--muted);
          cursor: grab;
          opacity: 0;
          touch-action: none;
          transition: opacity 0.12s ease;
        }

        .drag-handle .icon {
          width: 1rem;
          height: 1rem;
        }

        :scope:is(:hover, :focus-within) .drag-handle {
          opacity: 1;
        }

        @media (hover: none) {
          .drag-handle {
            opacity: 1;
          }
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
        display: grid;
        gap: 0.5rem;
      }
    </style>
    <p :if={@tasks == []} class="empty">{@empty}</p>
    <ul
      id={@id}
      class="task-list"
      phx-hook=".Outline"
      data-outline={@outline}
      data-nested={@nested}
    >
      <li
        :for={%{task: task, dates: d, depth: depth, children?: children?} <- @rows}
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
        <%!-- The keys move a row too; this is for pointers. Its own no-op
             click keeps a grab from opening the inspector. --%>
        <span
          :if={@outline}
          class="drag-handle"
          aria-hidden="true"
          title="Drag to move"
          phx-click={JS.dispatch("outline:noop")}
        >
          <Lucideicons.grip_vertical class="icon" />
        </span>
        <span :if={@outline or @nested} class="disclosure">
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
              <Lucideicons.square_slash class="icon" />
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
          <MarskalWeb.FormattedNotes.block text={task.notes} />
          <MarskalWeb.TagComponents.chips entries={Map.get(@tags, task.id, [])} />
        </div>
      </li>
    </ul>
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

      // The row keys of an outliner: Tab and Shift-Tab indent and outdent,
      // as do the macOS-style Cmd-] and Cmd-[ (Ctrl off a Mac).
      // Alt-Up and Alt-Down move among siblings, Up and Down move focus.
      const command = (e: KeyboardEvent) => e.metaKey || e.ctrlKey
      const plain = (e: KeyboardEvent) => !command(e) && !e.altKey

      const bracket = (e: KeyboardEvent, key: "[" | "]") => command(e) && !e.altKey && e.key === key

      const moves: Record<string, (event: KeyboardEvent) => boolean> = {
        "outline-indent": (e) => (plain(e) && e.key === "Tab" && !e.shiftKey) || bracket(e, "]"),
        "outline-outdent": (e) => (plain(e) && e.key === "Tab" && e.shiftKey) || bracket(e, "["),
        "outline-up": (e) => e.altKey && !command(e) && e.key === "ArrowUp",
        "outline-down": (e) => e.altKey && !command(e) && e.key === "ArrowDown",
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

      export default class extends ViewHook<HTMLUListElement> {
        focusId: string | null = null
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

          if (place.parent_id === drag.from.parent_id && place.after_id === drag.from.after_id) return
          this.focusId = drag.el.dataset.inspectId!
          this.pushEvent("outline-place", {id: this.focusId, ...place})
        }

        onKeydown = (event: KeyboardEvent) => {
          if (!(event.target instanceof HTMLElement)) return
          const row = event.target.closest<HTMLElement>(".task-row")
          const id = row?.dataset.inspectId
          if (!row || !id) return

          const move = Object.keys(moves).find((name) => moves[name]?.(event))
          if (move) {
            event.preventDefault()
            this.focusId = id
            this.pushEvent(move, {id})
            return
          }

          if (!plain(event) || (event.key !== "ArrowUp" && event.key !== "ArrowDown")) return
          const rows = Array.from(this.el.querySelectorAll<HTMLElement>(":scope > .task-row"))
          const next = rows[rows.indexOf(row) + (event.key === "ArrowUp" ? -1 : 1)]
          if (!next) return
          event.preventDefault()
          next.querySelector<HTMLElement>("button.select")?.focus()
        }

        mounted() {
          const outline = this.el.hasAttribute("data-outline")
          if (!outline && !this.el.hasAttribute("data-nested")) return
          this.handleEvent("outline-collapsed", ({ids}: {ids: string[]}) => save(ids))
          const ids = load()
          if (ids.length) this.pushEvent("outline-collapsed", {ids})

          // A nested list only collapses; its rows do not move.
          if (!outline) return
          this.el.addEventListener("keydown", this.onKeydown)
          this.el.addEventListener("pointerdown", this.onPointerDown)
          document.addEventListener("pointermove", this.onPointerMove)

          // The fallback drag, rather than native drag and drop, reports the
          // pointer throughout and works the same on touch.
          this.sortable = Sortable.create(this.el, {
            handle: ".drag-handle",
            draggable: ".task-row",
            filter: ".is-drag-hidden",
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
          if (!this.focusId) return
          const title = this.el.querySelector<HTMLElement>(`#task-${CSS.escape(this.focusId)} button.select`)
          if (title && document.activeElement !== title) title.focus()
          this.focusId = null
        }

        destroyed() {
          this.el.removeEventListener("keydown", this.onKeydown)
          this.el.removeEventListener("pointerdown", this.onPointerDown)
          document.removeEventListener("pointermove", this.onPointerMove)
          this.sortable?.destroy()
        }
      }
    </script>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :task, :any, required: true
  attr :projects, :list, required: true
  attr :class, :string, default: nil

  @doc """
  Where a task lives: the inbox, no project, or one project (ADR 0017).
  Read the submitted value back with `parse_location/1`.
  """
  def location_select(assigns) do
    assigns = assign(assigns, :location, Marskal.Tasks.location(assigns.task))

    ~H"""
    <select id={@id} class={@class} name={@name}>
      <option value="inbox" selected={@location == :inbox}>Inbox</option>
      <option value="none" selected={@location == :none}>No project</option>
      <optgroup :if={@projects != []} label="Projects">
        <option :for={project <- @projects} value={project.id} selected={@location == project.id}>
          {project.title}
        </option>
      </optgroup>
    </select>
    """
  end

  @doc "The location a `location_select/1` value names."
  def parse_location("inbox"), do: :inbox
  def parse_location(value) when value in ["none", ""], do: :none
  def parse_location(project_id) when is_binary(project_id), do: project_id

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
