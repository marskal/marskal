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

  def list(assigns) do
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

        :scope.is-unavailable .title {
          color: var(--muted);
        }

        :scope.is-resolved .title {
          color: var(--muted);
        }

        :scope.is-resolved:has(.check--done) .title {
          text-decoration: line-through;
        }

        .actions {
          display: flex;
          gap: 0.35rem;
          flex-shrink: 0;
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
          MapSet.member?(@unavailable, task.id) && "is-unavailable",
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
            :if={MapSet.member?(@unavailable, task.id) or (@mark_inbox and task.inbox)}
            class="marks"
          >
            <span :if={@mark_inbox and task.inbox} class="mark mark--inbox">Inbox</span>
            <span :if={MapSet.member?(@unavailable, task.id)} class="mark mark--unavailable">
              Unavailable
            </span>
          </span>
          <MarskalWeb.FormattedNotes.block text={task.notes} />
          <MarskalWeb.TagComponents.chips entries={Map.get(@tags, task.id, [])} />
        </div>
        <span :if={:clarify in @actions} class="actions">
          <button :if={task.inbox} type="button" phx-click="clarify" phx-value-id={task.id}>
            Clarify
          </button>
          <button :if={!task.inbox} type="button" phx-click="unclarify" phx-value-id={task.id}>
            Back to inbox
          </button>
        </span>
      </li>
    </ul>
    """
  end

  defp check_event(%{state: :to_do}), do: "complete"
  defp check_event(_task), do: "reopen"

  defp check_label(%{state: :to_do}), do: "Mark as done"
  defp check_label(_task), do: "Reopen"

  defp check_class(%{state: :done}), do: "check check--done"
  defp check_class(%{state: :dropped}), do: "check check--dropped"
  defp check_class(_task), do: "check"
end
