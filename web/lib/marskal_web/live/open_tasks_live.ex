defmodule MarskalWeb.OpenTasksLive do
  use MarskalWeb, :live_view

  use MarskalWeb.TaskActions,
    reload: &load_tasks/1,
    missing: "That task is not available."

  import MarskalWeb.TaskList, only: [assign_tasks: 2, reset_tasks: 1]

  alias Marskal.Tasks

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Open tasks") |> assign(:show_unavailable, nil)}
  end

  # Tasks made unavailable by tag state (ADR 0005), and deferred ones
  # (ADR 0006), are hidden unless ?unavailable=1.
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
        deferred={@task_tags.deferred}
        dates={@task_tags.dates}
        resolved={@task_tags.resolved}
        parents={@task_tags.parents}
        zone={Marskal.Accounts.timezone(@current_scope.user)}
        empty="No open tasks."
        actions={[:complete]}
        inspector={@inspector}
      />
    </Layouts.app>
    """
  end

  defp load_tasks(socket) do
    user = socket.assigns.current_scope.user
    assign_tasks(socket, Tasks.list_open(user, unavailable: socket.assigns.show_unavailable))
  end
end
