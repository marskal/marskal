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
          gap: 0.75rem;
          align-items: flex-start;
          justify-content: space-between;
          padding: 0.65rem 0.75rem;
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }

        .body {
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
        <div class="body">
          <.link navigate={~p"/tasks/#{task.id}"} class="title">{task.title}</.link>
          <MarskalWeb.FormattedNotes.block text={task.notes} />
        </div>
        <span class="actions">
          <button :if={:clarify in @actions} type="button" phx-click="clarify" phx-value-id={task.id}>
            Clarify
          </button>
          <button
            :if={:complete in @actions}
            type="button"
            phx-click="complete"
            phx-value-id={task.id}
          >
            Done
          </button>
          <button :if={:drop in @actions} type="button" phx-click="drop" phx-value-id={task.id}>
            Drop
          </button>
        </span>
      </li>
    </ul>
    """
  end
end
