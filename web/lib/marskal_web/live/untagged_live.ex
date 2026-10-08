defmodule MarskalWeb.UntaggedLive do
  use MarskalWeb, :live_view
  use MarskalWeb.TaskActions, reload: &load/1

  import MarskalWeb.TaskList, only: [assign_tasks: 2]

  alias Marskal.Tags

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Untagged") |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_nav={:untagged}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <h1>Untagged</h1>
      <p class="lede">To-do tasks with no tags of their own or from their project.</p>

      <MarskalWeb.TaskComponents.list
        id="untagged-tasks"
        tasks={@tasks}
        tags={@task_tags.tags}
        unavailable={@task_tags.unavailable}
        deferred={@task_tags.deferred}
        dates={@task_tags.dates}
        resolved={@task_tags.resolved}
        parents={@task_tags.parents}
        repeating={@task_tags.repeating}
        zone={Marskal.Accounts.timezone(@current_scope.user)}
        mark_inbox
        empty="Every task has a tag."
        actions={[:complete]}
        inspector={@inspector}
      />
    </Layouts.app>
    """
  end

  defp load(socket) do
    assign_tasks(socket, Tags.untagged_tasks(socket.assigns.current_scope.user))
  end
end
