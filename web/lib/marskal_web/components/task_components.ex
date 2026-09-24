defmodule MarskalWeb.TaskComponents do
  use MarskalWeb, :html

  attr :id, :string, required: true
  attr :tasks, :list, required: true
  attr :empty, :string, required: true
  attr :actions, :list, required: true

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
      <li :for={task <- @tasks} id={"task-#{task.id}"} class="task-row">
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
          <.link navigate={~p"/tasks/#{task.id}"} class="title">{task.title}</.link>
          <MarskalWeb.FormattedNotes.block text={task.notes} />
        </div>
        <span class="actions">
          <button :if={:clarify in @actions} type="button" phx-click="clarify" phx-value-id={task.id}>
            Clarify
          </button>
          <button
            :if={:drop in @actions and task.state == :to_do}
            type="button"
            phx-click="drop"
            phx-value-id={task.id}
          >
            Drop
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
