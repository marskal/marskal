defmodule MarskalWeb.TaskComponents do
  use MarskalWeb, :html

  attr :id, :string, required: true
  attr :tasks, :list, required: true
  attr :empty, :string, required: true
  attr :actions, :list, required: true

  def list(assigns) do
    ~H"""
    <p :if={@tasks == []} class="empty">{@empty}</p>
    <ul id={@id} class="task-list">
      <li :for={task <- @tasks} id={"task-#{task.id}"} class="task-row">
        <span class="title">{task.title}</span>
        <span class="actions">
          <button :if={:clarify in @actions} type="button" phx-click="clarify" phx-value-id={task.id}>
            Clarify
          </button>
          <button :if={:complete in @actions} type="button" phx-click="complete" phx-value-id={task.id}>
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
