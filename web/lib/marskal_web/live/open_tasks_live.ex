defmodule MarskalWeb.OpenTasksLive do
  use MarskalWeb, :live_view

  use MarskalWeb.TaskActions,
    reload: &load_tasks/1,
    missing: "That task is not available."

  import MarskalWeb.TaskList, only: [assign_tasks: 2]

  alias Marskal.Tasks

  # The open stream, and :flagged, its flagged tasks with the inbox's
  # (ADR 0025).
  @impl true
  def mount(_params, _session, socket) do
    title = if socket.assigns.live_action == :flagged, do: "Flagged", else: "Open tasks"

    {:ok,
     socket
     |> MarskalWeb.Outline.attach()
     |> assign(:page_title, title)}
  end

  # Opening the inspector patches this page. That is not a new view, so
  # rows kept for undo stay. A visibility change resets them itself.
  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, load_tasks(socket)}
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
      visibility={assigns[:visibility]}
    >
      <h1>{@page_title}</h1>
      <p class="lede">
        {if @flagged?,
          do: "Open tasks flagged by themselves or by their project.",
          else: "Work out of the inbox, still to do."}
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
        actions={[:complete]}
        inspector={@inspector}
      >
        <:empty_state>
          <.empty_state :if={@flagged?} id="flagged-empty" title="Nothing flagged">
            <:icon><Lucideicons.flag class="icon" /></:icon>
            Flag a task or project to keep it here.
          </.empty_state>
          <.empty_state :if={!@flagged?} id="open-empty" title="Nothing to do">
            <:icon><Lucideicons.circle_check_big class="icon" /></:icon>
            Tasks you move out of the inbox show up here until they are done.
          </.empty_state>
        </:empty_state>
      </MarskalWeb.TaskComponents.list>
    </Layouts.app>
    """
  end

  defp load_tasks(socket) do
    user = socket.assigns.current_scope.user
    opts = [show: socket.assigns.visibility]

    # Subtasks show under their parents (ADR 0009). Flagged stays flat:
    # a parent task does not flag its subtasks (ADR 0025).
    tasks =
      if socket.assigns.live_action == :flagged,
        do: Tasks.list_flagged(user, opts),
        else: user |> Tasks.list_open(opts) |> then(&Tasks.with_ancestors(user, &1))

    assign_tasks(socket, tasks)
  end
end
