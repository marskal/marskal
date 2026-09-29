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

  attr :zone, :string, default: "Europe/Copenhagen", doc: "the user's zone, for date labels"

  def list(assigns) do
    assigns =
      assign(assigns, now: DateTime.utc_now(), today: Marskal.Dates.today(assigns.zone))

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
    <ul id={@id} class="task-list">
      <li
        :for={task <- @tasks}
        id={"task-#{task.id}"}
        class={[
          "task-row",
          MarskalWeb.Inspector.selected?(:task, task.id, @inspector) && "is-selected",
          (MapSet.member?(@unavailable, task.id) or MapSet.member?(@deferred, task.id)) &&
            "is-unavailable",
          task.state != :to_do && "is-resolved"
        ]}
        data-inspect-type="task"
        data-inspect-id={task.id}
        aria-current={MarskalWeb.Inspector.selected?(:task, task.id, @inspector) && "true"}
        phx-click="inspect"
        phx-value-type="task"
        phx-value-id={task.id}
      >
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
            {task.title}
          </button>
          <span
            :if={
              (@mark_inbox and task.inbox) or task.planned_at != nil or task.due_at != nil or
                MapSet.member?(@unavailable, task.id) or MapSet.member?(@deferred, task.id)
            }
            class="marks"
          >
            <span :if={@mark_inbox and task.inbox} class="mark mark--inbox">Inbox</span>
            <span :if={MapSet.member?(@unavailable, task.id)} class="mark mark--unavailable">
              Unavailable
            </span>
            <span :if={MapSet.member?(@deferred, task.id)} class="mark mark--deferred">
              {deferred_label(task, @zone, @today, @now)}
            </span>
            <span
              :if={task.planned_at}
              class={["mark mark--planned", planned_today?(task, @zone, @today) && "mark--today"]}
            >
              Planned {MarskalWeb.DateFields.short(task.planned_at, :planned_at, @zone, @today)}
            </span>
            <span
              :if={task.due_at}
              class={["mark mark--due", Marskal.Dates.overdue?(task, @now) && "mark--overdue"]}
            >
              Due {MarskalWeb.DateFields.short(task.due_at, :due_at, @zone, @today)}
            </span>
          </span>
          <MarskalWeb.FormattedNotes.block text={task.notes} />
          <MarskalWeb.TagComponents.chips entries={Map.get(@tags, task.id, [])} />
        </div>
      </li>
    </ul>
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

  # A task can be deferred by its project, with no Defer of its own.
  defp deferred_label(task, zone, today, now) do
    if Marskal.Dates.deferred?(task, now) and task.defer_until,
      do:
        "Deferred until #{MarskalWeb.DateFields.short(task.defer_until, :defer_until, zone, today)}",
      else: "Deferred"
  end

  defp planned_today?(task, zone, today) do
    task.state == :to_do and elem(Marskal.Dates.to_local(task.planned_at, zone), 0) == today
  end

  defp check_event(%{state: :to_do}), do: "complete"
  defp check_event(_task), do: "reopen"

  defp check_label(%{state: :to_do}), do: "Mark as done"
  defp check_label(_task), do: "Reopen"

  defp check_class(%{state: :done}), do: "check check--done"
  defp check_class(%{state: :dropped}), do: "check check--dropped"
  defp check_class(_task), do: "check"
end
