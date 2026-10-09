defmodule MarskalWeb.OpenTasksLive do
  use MarskalWeb, :live_view

  use MarskalWeb.TaskActions,
    reload: &load_tasks/1,
    missing: "That task is not available."

  import MarskalWeb.TaskList, only: [assign_tasks: 2, reset_tasks: 1]

  alias Marskal.Tasks

  # The open stream, and :flagged, its flagged tasks with the inbox's
  # (ADR 0025).
  @impl true
  def mount(_params, _session, socket) do
    title = if socket.assigns.live_action == :flagged, do: "Flagged", else: "Open tasks"

    {:ok,
     socket
     |> MarskalWeb.Outline.attach()
     |> assign(:page_title, title)
     |> assign(:show_unavailable, nil)}
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
    assigns = assign(assigns, :flagged?, assigns.live_action == :flagged)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_nav={if @flagged?, do: :flagged, else: :open}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <h1>{@page_title}</h1>
      <p class="lede">
        {if @flagged?,
          do: "Open tasks flagged by themselves or by their project.",
          else: "Work out of the inbox, still to do."}
        <.link :if={!@show_unavailable} patch={view_path(@flagged?, unavailable: 1)}>
          Show unavailable
        </.link>
        <.link :if={@show_unavailable} patch={view_path(@flagged?, [])}>Hide unavailable</.link>
      </p>

      <MarskalWeb.TaskComponents.list
        id={if @flagged?, do: "flagged-tasks", else: "open-tasks"}
        tasks={@tasks}
        tags={@task_tags.tags}
        unavailable={@task_tags.unavailable}
        deferred={@task_tags.deferred}
        dates={@task_tags.dates}
        resolved={@task_tags.resolved}
        parents={@task_tags.parents}
        repeating={@task_tags.repeating}
        flagged={@task_tags.flagged}
        zone={Marskal.Accounts.timezone(@current_scope.user)}
        nested={!@flagged?}
        collapsed={@collapsed}
        mark_inbox={@flagged?}
        empty={if @flagged?, do: "Nothing flagged.", else: "No open tasks."}
        actions={[:complete]}
        inspector={@inspector}
      />
    </Layouts.app>
    """
  end

  defp view_path(true, []), do: ~p"/flagged"
  defp view_path(true, query), do: ~p"/flagged?#{query}"
  defp view_path(false, []), do: ~p"/"
  defp view_path(false, query), do: ~p"/?#{query}"

  defp load_tasks(socket) do
    user = socket.assigns.current_scope.user
    opts = [unavailable: socket.assigns.show_unavailable]

    # Subtasks show under their parents (ADR 0009). Flagged stays flat:
    # a parent task does not flag its subtasks (ADR 0025).
    tasks =
      if socket.assigns.live_action == :flagged,
        do: Tasks.list_flagged(user, opts),
        else: user |> Tasks.list_open(opts) |> then(&Tasks.with_ancestors(user, &1))

    assign_tasks(socket, tasks)
  end
end
