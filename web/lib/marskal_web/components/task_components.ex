defmodule MarskalWeb.TaskComponents do
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

  attr :collapsed, :any, default: MapSet.new(), doc: "ids whose subtasks the outline hides"

  attr :zone, :string, default: "Europe/Copenhagen", doc: "the user's zone, for date labels"

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
    <ul id={@id} class="task-list" phx-hook=".Outline" data-outline={@outline}>
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
        data-depth={@outline && depth}
        data-inspect-type="task"
        data-inspect-id={task.id}
        aria-current={MarskalWeb.Inspector.selected?(:task, task.id, @inspector) && "true"}
        phx-click="inspect"
        phx-value-type="task"
        phx-value-id={task.id}
      >
        <span :if={@outline} class="disclosure">
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
            <span :if={!@outline && @parents[task.id]} class="crumb">
              {@parents[task.id].title}<span class="chevron" aria-hidden="true">›</span>
            </span>
            {task.title}
          </button>
          <span
            :if={
              (@mark_inbox and task.inbox) or d.planned_at != nil or d.due_at != nil or
                MapSet.member?(@unavailable, task.id) or MapSet.member?(@deferred, task.id)
            }
            class="marks"
          >
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
      // Alt-Up and Alt-Down move among siblings, Up and Down move focus.
      const moves: Record<string, (event: KeyboardEvent) => boolean> = {
        "outline-indent": (e) => e.key === "Tab" && !e.shiftKey,
        "outline-outdent": (e) => e.key === "Tab" && e.shiftKey,
        "outline-up": (e) => e.altKey && e.key === "ArrowUp",
        "outline-down": (e) => e.altKey && e.key === "ArrowDown",
      }

      export default class extends ViewHook<HTMLUListElement> {
        focusId: string | null = null

        onKeydown = (event: KeyboardEvent) => {
          if (!(event.target instanceof HTMLElement)) return
          const row = event.target.closest<HTMLElement>(".task-row")
          const id = row?.dataset.inspectId
          if (!row || !id || event.ctrlKey || event.metaKey) return

          const move = Object.keys(moves).find((name) => moves[name]?.(event))
          if (move) {
            event.preventDefault()
            this.focusId = id
            this.pushEvent(move, {id})
            return
          }

          if (event.altKey || (event.key !== "ArrowUp" && event.key !== "ArrowDown")) return
          const rows = Array.from(this.el.querySelectorAll<HTMLElement>(":scope > .task-row"))
          const next = rows[rows.indexOf(row) + (event.key === "ArrowUp" ? -1 : 1)]
          if (!next) return
          event.preventDefault()
          next.querySelector<HTMLElement>("button.select")?.focus()
        }

        mounted() {
          if (!this.el.hasAttribute("data-outline")) return
          this.el.addEventListener("keydown", this.onKeydown)
          this.handleEvent("outline-collapsed", ({ids}: {ids: string[]}) => save(ids))
          const ids = load()
          if (ids.length) this.pushEvent("outline-collapsed", {ids})
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
  # list starts at the top.
  defp rows(%{outline: false} = assigns),
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
    |> Enum.sort_by(&{&1.rank, &1.id})
    |> Enum.flat_map(fn task ->
      children? = Map.has_key?(children, task.id)

      below =
        if children? and not MapSet.member?(assigns.collapsed, task.id),
          do: walk(children, task.id, depth + 1, assigns),
          else: []

      [row(task, assigns.dates, depth, children?) | below]
    end)
  end

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

  defp check_event(%{state: :to_do}), do: "complete"
  defp check_event(_task), do: "reopen"

  defp check_label(%{state: :to_do}), do: "Mark as done"
  defp check_label(_task), do: "Reopen"

  defp check_class(%{state: :done}), do: "check check--done"
  defp check_class(%{state: :dropped}), do: "check check--dropped"
  defp check_class(_task), do: "check"
end
