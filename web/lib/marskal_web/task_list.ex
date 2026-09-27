defmodule MarskalWeb.TaskList do
  @moduledoc """
  Assigns a task list with what `MarskalWeb.TaskComponents.list/1` shows
  about its tags: effective tags and unavailable ids (ADR 0005).
  """

  import Phoenix.Component, only: [assign: 3]

  def assign_tasks(socket, tasks) do
    socket
    |> assign(:tasks, tasks)
    |> assign(:task_tags, Marskal.Tags.annotate(socket.assigns.current_scope.user, tasks))
  end
end
