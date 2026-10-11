defmodule MarskalWeb.TaskController do
  use MarskalWeb, :controller

  alias Marskal.Tasks

  # A task has no page of its own: its link opens the inspector on it where
  # it lives.
  def show(conn, %{"id" => id}) do
    case Tasks.get_task(conn.assigns.current_scope.user, id) do
      nil ->
        conn |> put_flash(:error, "That task is not available.") |> redirect(to: ~p"/")

      task ->
        redirect(conn, to: location_path(task))
    end
  end

  defp location_path(%{project_id: project_id} = task) when not is_nil(project_id),
    do: ~p"/projects/#{project_id}?#{[task: task.id]}"

  defp location_path(%{inbox: true} = task), do: ~p"/inbox?#{[task: task.id]}"
  defp location_path(task), do: ~p"/?#{[task: task.id]}"
end
