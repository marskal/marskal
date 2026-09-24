defmodule MarskalWeb.OpenTasksLive do
  use MarskalWeb, :live_view

  alias Marskal.Tasks

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Open tasks")
     |> assign(:tasks, Tasks.list_open(user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_nav={:open}>
      <h1>Open tasks</h1>
      <p class="lede">Clarified work, still to do.</p>

      <MarskalWeb.TaskComponents.list
        id="open-tasks"
        tasks={@tasks}
        empty="No open tasks."
        actions={[:complete, :drop]}
      />
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("complete", %{"id" => id}, socket), do: act(socket, id, &Tasks.complete_task/3)
  def handle_event("drop", %{"id" => id}, socket), do: act(socket, id, &Tasks.drop_task/3)
  def handle_event("reopen", %{"id" => id}, socket), do: act(socket, id, &Tasks.reopen_task/3)

  defp act(socket, id, fun) do
    user = socket.assigns.current_scope.user

    case fun.(user, id, Ecto.UUID.generate()) do
      {:ok, _task} ->
        {:noreply, assign(socket, :tasks, Tasks.list_open(user))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That task is not available.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update task.")}
    end
  end
end
