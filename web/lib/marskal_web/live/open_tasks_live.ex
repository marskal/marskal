defmodule MarskalWeb.OpenTasksLive do
  use MarskalWeb, :live_view

  import MarskalWeb.TaskList, only: [assign_tasks: 2, reset_tasks: 1]

  alias Marskal.Tasks

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Open tasks") |> assign(:show_unavailable, nil)}
  end

  # Tasks made unavailable by tag state (ADR 0005) are hidden unless
  # ?unavailable=1; deferred tasks will join the same toggle (ADR 0006).
  # Flipping it is a new view, so kept rows go; opening the inspector is not.
  @impl true
  def handle_params(params, _uri, socket) do
    show = params["unavailable"] == "1"

    socket
    |> then(&if(&1.assigns.show_unavailable == show, do: &1, else: reset_tasks(&1)))
    |> assign(:show_unavailable, show)
    |> load_tasks()
    |> then(&{:noreply, &1})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_nav={:open}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <h1>Open tasks</h1>
      <p class="lede">
        Work out of the inbox, still to do.
        <.link :if={!@show_unavailable} patch={~p"/?#{[unavailable: 1]}"}>Show unavailable</.link>
        <.link :if={@show_unavailable} patch={~p"/"}>Hide unavailable</.link>
      </p>

      <MarskalWeb.TaskComponents.list
        id="open-tasks"
        tasks={@tasks}
        tags={@task_tags.tags}
        unavailable={@task_tags.unavailable}
        empty="No open tasks."
        actions={[:complete]}
        inspector={@inspector}
      />
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:marskal_change, _type, _id}, socket) do
    {:noreply, load_tasks(socket)}
  end

  @impl true
  def handle_event("complete", %{"id" => id}, socket), do: act(socket, id, &Tasks.complete_task/3)
  def handle_event("reopen", %{"id" => id}, socket), do: act(socket, id, &Tasks.reopen_task/3)

  defp act(socket, id, fun) do
    user = socket.assigns.current_scope.user

    case fun.(user, id, Ecto.UUID.generate()) do
      {:ok, _task} ->
        {:noreply, load_tasks(socket)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That task is not available.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update task.")}
    end
  end

  defp load_tasks(socket) do
    user = socket.assigns.current_scope.user
    assign_tasks(socket, Tasks.list_open(user, unavailable: socket.assigns.show_unavailable))
  end
end
