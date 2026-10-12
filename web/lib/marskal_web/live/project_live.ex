defmodule MarskalWeb.ProjectLive do
  use MarskalWeb, :live_view

  import MarskalWeb.TaskList, only: [assign_tasks: 2]

  alias Marskal.Projects
  alias Marskal.Tasks

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Projects.get_project(user, id) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "That project is not available.") |> redirect(to: ~p"/")}

      project ->
        {:ok, socket |> MarskalWeb.Outline.attach() |> assign_project(user, project)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_id={@project.id}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <p :if={@folder} class="lede">
        <.link
          navigate={MarskalWeb.NavComponents.record_path(:folder, @folder.id)}
          data-opens-inspector
        >{@folder.name}</.link>
      </p>
      <MarskalWeb.NavComponents.page_heading type={:project} id={@project.id} inspector={@inspector}>
        {@project.title}
      </MarskalWeb.NavComponents.page_heading>
      <p :if={@project.url} class="lede"><MarskalWeb.UrlLink.link url={@project.url} text /></p>
      <MarskalWeb.FormattedNotes.block text={@project.notes} class="lede notes" />
      <.add_form
        id="new-project-task"
        for={@form}
        field={@form[:title]}
        label="Add a task"
        command_id={@command_id}
        phx-submit="create"
      />

      <MarskalWeb.TaskComponents.list
        id="project-tasks"
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
        actions={[:complete]}
        inspector={@inspector}
      />

      <.empty_state
        :if={!@open? and @project.state != :to_do}
        id="project-resolved"
        title={
          if @project.state == :done, do: "This project is done", else: "This project is dropped"
        }
      >
        <:icon><Lucideicons.archive class="icon" /></:icon>
        Its tasks are resolved along with it.
        <:actions>
          <button type="button" phx-click="reopen">Reopen</button>
        </:actions>
      </.empty_state>
      <.empty_state
        :if={!@open? and @project.state == :to_do and @has_tasks?}
        id="project-finished"
        title="Nothing left to do"
      >
        <:icon><Lucideicons.circle_check_big class="icon" /></:icon>
        Every task here is resolved. Is the project done too?
        <:actions>
          <button type="button" class="btn-primary" phx-click="complete">
            Mark project done
          </button>
          <button type="button" phx-click="drop">Drop project</button>
        </:actions>
      </.empty_state>
      <.empty_state
        :if={!@open? and @project.state == :to_do and !@has_tasks?}
        id="project-empty"
        title="No tasks yet"
      >
        <:icon><Lucideicons.list_checks class="icon" /></:icon>
        What is the next thing to do? Add it above.
      </.empty_state>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:marskal_change, _type, _id}, socket) do
    user = socket.assigns.current_scope.user
    project = Projects.get_project(user, socket.assigns.project.id) || socket.assigns.project

    {:noreply, assign_records(socket, user, project)}
  end

  @impl true
  def handle_event("create", %{"task" => params, "command_id" => command_id}, socket) do
    user = socket.assigns.current_scope.user
    attrs = Map.put(params, "project_id", socket.assigns.project.id)

    case Tasks.create_task(user, attrs, command_id) do
      {:ok, _task} ->
        {:noreply, assign_project(socket, user, socket.assigns.project)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "task"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add task.")}
    end
  end

  def handle_event("complete", %{"id" => id}, socket),
    do: task_act(socket, id, &Tasks.complete_task/3)

  def handle_event("reopen", %{"id" => id}, socket),
    do: task_act(socket, id, &Tasks.reopen_task/3)

  def handle_event("complete", _params, socket), do: act(socket, &Projects.complete_project/3)
  def handle_event("drop", _params, socket), do: act(socket, &Projects.drop_project/3)
  def handle_event("reopen", _params, socket), do: act(socket, &Projects.reopen_project/3)

  defp act(socket, fun) do
    user = socket.assigns.current_scope.user

    case fun.(user, socket.assigns.project.id, Ecto.UUID.generate(version: 7)) do
      {:ok, project} -> {:noreply, assign_project(socket, user, project)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update project.")}
    end
  end

  defp task_act(socket, id, fun) do
    user = socket.assigns.current_scope.user

    case fun.(user, id, Ecto.UUID.generate(version: 7)) do
      {:ok, _} -> {:noreply, assign_project(socket, user, socket.assigns.project)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update task.")}
    end
  end

  defp assign_project(socket, user, project) do
    socket
    |> assign_records(user, project)
    |> assign(:command_id, Ecto.UUID.generate(version: 7))
    |> assign(:form, to_form(%{"title" => ""}, as: "task"))
  end

  # Leaves the capture form alone, so a broadcast does not clear typing.
  defp assign_records(socket, user, project) do
    open_tasks = Tasks.list_project_tasks(user, project.id)

    folder =
      if project.project_folder_id do
        Marskal.ProjectFolders.get_folder(user, project.project_folder_id)
      end

    socket
    |> assign(:page_title, project.title)
    |> assign(:project, project)
    |> assign(:folder, folder)
    |> assign(:open?, open_tasks != [])
    |> assign(:has_tasks?, open_tasks != [] or Tasks.project_has_tasks?(user, project.id))
    |> assign_tasks(open_tasks)
  end
end
