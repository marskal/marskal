defmodule MarskalWeb.InboxLive do
  use MarskalWeb, :live_view

  import MarskalWeb.TaskList, only: [assign_tasks: 2]

  alias Marskal.Tasks

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Inbox")
     |> MarskalWeb.Outline.attach()
     |> assign(:command_id, Ecto.UUID.generate(version: 7))
     |> assign(:form, to_form(%{"title" => ""}, as: "task"))
     |> assign_tasks(Tasks.list_inbox(user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_nav={:inbox}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <h1>Inbox</h1>
      <p class="lede">
        New captures. Move one to a project, or to no project, to put it on the open list.
      </p>

      <.add_form
        id="new-task"
        for={@form}
        field={@form[:title]}
        label="Add to inbox"
        command_id={@command_id}
        autofocus
        phx-submit="create"
      />

      <MarskalWeb.TaskComponents.list
        id="inbox-tasks"
        tasks={@tasks}
        tags={@task_tags.tags}
        unavailable={@task_tags.unavailable}
        deferred={@task_tags.deferred}
        dates={@task_tags.dates}
        resolved={@task_tags.resolved}
        parents={@task_tags.parents}
        repeating={@task_tags.repeating}
        flagged={@task_tags.flagged}
        outline
        collapsed={@collapsed}
        zone={Marskal.Accounts.timezone(@current_scope.user)}
        empty="Nothing in the inbox."
        actions={[:complete]}
        inspector={@inspector}
      />
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:marskal_change, _type, _id}, socket) do
    {:noreply, assign_tasks(socket, Tasks.list_inbox(socket.assigns.current_scope.user))}
  end

  @impl true
  def handle_event("create", %{"task" => params, "command_id" => command_id}, socket) do
    user = socket.assigns.current_scope.user

    case Tasks.create_task(user, params, command_id) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Added.")
         |> assign(:command_id, Ecto.UUID.generate(version: 7))
         |> assign(:form, to_form(%{"title" => ""}, as: "task"))
         |> assign_tasks(Tasks.list_inbox(user))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "task"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not add task.")}
    end
  end

  def handle_event("complete", %{"id" => id}, socket), do: act(socket, id, &Tasks.complete_task/3)
  def handle_event("reopen", %{"id" => id}, socket), do: act(socket, id, &Tasks.reopen_task/3)

  defp act(socket, id, fun) do
    user = socket.assigns.current_scope.user

    case fun.(user, id, Ecto.UUID.generate(version: 7)) do
      {:ok, _task} ->
        {:noreply, assign_tasks(socket, Tasks.list_inbox(user))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That task is not available.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update task.")}
    end
  end
end
