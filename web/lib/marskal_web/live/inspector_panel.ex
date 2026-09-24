defmodule MarskalWeb.InspectorPanel do
  use MarskalWeb, :live_component

  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Tasks

  defp task_states, do: [{"To-Do", "to_do"}, {"Done", "done"}, {"Dropped", "dropped"}]
  defp folder_states, do: [{"Active", "active"}, {"Dropped", "dropped"}]

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if Map.has_key?(socket.assigns, :loaded_selection) and
           socket.assigns.loaded_selection == assigns.selection do
        socket
      else
        socket
        |> assign(:record, load(assigns.user, assigns.selection))
        |> assign(:loaded_selection, assigns.selection)
        |> assign(:error, nil)
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.inspector-form) {
        :scope {
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }

        .errors {
          margin: 0;
          padding: 0.5rem 0.65rem;
          border-radius: 6px;
          background: var(--danger-bg);
          font-size: 0.9rem;
        }

        .form {
          display: flex;
          flex-direction: column;
          gap: 0.85rem;
        }

        .field {
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
        }

        .field label {
          font-size: 0.8rem;
          font-weight: 600;
          color: var(--muted);
        }

        .field--check {
          flex-direction: row;
          align-items: flex-start;
          gap: 0.55rem;
        }

        .check-copy {
          display: flex;
          flex-direction: column;
          gap: 0.15rem;
          min-width: 0;
        }

        .check-copy label {
          font-size: 0.9rem;
          font-weight: 600;
          color: var(--text);
        }

        .hint {
          margin: 0;
          font-size: 0.8rem;
          color: var(--muted);
        }

        .input {
          width: 100%;
          padding: 0.45rem 0.6rem;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: var(--bg);
          color: var(--text);
          font: inherit;
        }

        textarea.input {
          resize: vertical;
          min-height: 8rem;
          line-height: 1.45;
        }

        .actions {
          display: flex;
          justify-content: flex-end;
          align-items: center;
          gap: 0.5rem;
        }

        .open {
          margin-right: auto;
          color: var(--muted);
          text-decoration: none;
          font-size: 0.9rem;
        }

        .meta {
          margin: 0;
          padding-top: 0.75rem;
          border-top: 1px solid var(--border);
          display: flex;
          flex-direction: column;
          gap: 0.35rem;
          font-size: 0.8rem;
          color: var(--muted);
        }

        .meta div {
          display: flex;
          justify-content: space-between;
          gap: 0.75rem;
        }

        .meta dd {
          margin: 0;
          text-align: right;
        }
      }
    </style>
    <div id={@id}>
      <p :if={@selection == nil} class="app-inspector__empty">
        Select a task, project, or folder to edit.
      </p>
      <p :if={@selection && @record == nil} class="app-inspector__empty">
        That item is not available.
      </p>
      <.task_form
        :if={match?(%Tasks.Task{}, @record)}
        myself={@myself}
        record={@record}
        user={@user}
        error={@error}
      />
      <.project_form
        :if={match?(%Projects.Project{}, @record)}
        myself={@myself}
        record={@record}
        user={@user}
        error={@error}
      />
      <.folder_form
        :if={match?(%ProjectFolders.ProjectFolder{}, @record)}
        myself={@myself}
        record={@record}
        user={@user}
        error={@error}
      />
    </div>
    """
  end

  attr :myself, :any, required: true
  attr :record, :any, required: true
  attr :user, :any, required: true
  attr :error, :string, default: nil

  defp task_form(assigns) do
    ~H"""
    <section class="inspector-form" data-inspect-type="task" data-inspect-id={@record.id}>
      <p :if={@error} class="errors" role="alert">{@error}</p>
      <form id="inspector-task" class="form" phx-change="save" phx-submit="save" phx-target={@myself}>
        <div class="field">
          <label for="inspector-task-title">Title</label>
          <input
            id="inspector-task-title"
            class="input"
            type="text"
            name="task[title]"
            value={@record.title}
            required
            autocomplete="off"
            phx-debounce="300"
          />
        </div>
        <div class="field">
          <label for="inspector-task-notes">Notes</label>
          <textarea
            id="inspector-task-notes"
            class="input"
            name="task[notes]"
            rows="8"
            placeholder="Markdown is fine…"
            phx-debounce="300"
          >{@record.notes}</textarea>
        </div>
        <div class="field">
          <label for="inspector-task-project">Project</label>
          <select id="inspector-task-project" class="input" name="task[project_id]">
            <option value="">No project</option>
            <option
              :for={project <- task_projects(@user, @record)}
              value={project.id}
              selected={project.id == @record.project_id}
            >
              {project.title}
            </option>
          </select>
        </div>
        <div class="field field--check">
          <input type="hidden" name="task[inbox]" value="false" />
          <input
            id="inspector-task-inbox"
            class="checkbox"
            type="checkbox"
            name="task[inbox]"
            value="true"
            checked={@record.inbox}
          />
          <div class="check-copy">
            <label for="inspector-task-inbox">Inbox</label>
            <p class="hint">Unclarified capture. Uncheck to move it to open tasks.</p>
          </div>
        </div>
        <div class="field">
          <label for="inspector-task-state">State</label>
          <select id="inspector-task-state" class="input" name="task[state]">
            <option
              :for={{label, value} <- task_states()}
              value={value}
              selected={value == Atom.to_string(@record.state)}
            >
              {label}
            </option>
          </select>
        </div>
        <div class="actions">
          <.link navigate={~p"/tasks/#{@record.id}"} class="open">Open task</.link>
        </div>
      </form>
      <.meta record={@record} />
    </section>
    """
  end

  attr :myself, :any, required: true
  attr :record, :any, required: true
  attr :user, :any, required: true
  attr :error, :string, default: nil

  defp project_form(assigns) do
    ~H"""
    <section class="inspector-form" data-inspect-type="project" data-inspect-id={@record.id}>
      <p :if={@error} class="errors" role="alert">{@error}</p>
      <form
        id="inspector-project"
        class="form"
        phx-change="save"
        phx-submit="save"
        phx-target={@myself}
      >
        <div class="field">
          <label for="inspector-project-title">Title</label>
          <input
            id="inspector-project-title"
            class="input"
            type="text"
            name="project[title]"
            value={@record.title}
            required
            autocomplete="off"
            phx-debounce="300"
          />
        </div>
        <div class="field">
          <label for="inspector-project-notes">Notes</label>
          <textarea
            id="inspector-project-notes"
            class="input"
            name="project[notes]"
            rows="8"
            placeholder="What does done look like? Markdown is fine."
            phx-debounce="300"
          >{@record.notes}</textarea>
        </div>
        <div class="field">
          <label for="inspector-project-folder">Folder</label>
          <select id="inspector-project-folder" class="input" name="project[project_folder_id]">
            <option value="">Unfiled</option>
            <option
              :for={folder <- ProjectFolders.list_all(@user)}
              value={folder.id}
              selected={folder.id == @record.project_folder_id}
            >
              {folder.name}
            </option>
          </select>
        </div>
        <div class="field">
          <label for="inspector-project-state">State</label>
          <select id="inspector-project-state" class="input" name="project[state]">
            <option
              :for={{label, value} <- task_states()}
              value={value}
              selected={value == Atom.to_string(@record.state)}
            >
              {label}
            </option>
          </select>
        </div>
        <div class="actions">
          <.link navigate={~p"/projects/#{@record.id}"} class="open">Open project</.link>
        </div>
      </form>
      <.meta record={@record} />
    </section>
    """
  end

  attr :myself, :any, required: true
  attr :record, :any, required: true
  attr :user, :any, required: true
  attr :error, :string, default: nil

  defp folder_form(assigns) do
    ~H"""
    <section class="inspector-form" data-inspect-type="folder" data-inspect-id={@record.id}>
      <p :if={@error} class="errors" role="alert">{@error}</p>
      <form
        id="inspector-folder"
        class="form"
        phx-change="save"
        phx-submit="save"
        phx-target={@myself}
      >
        <div class="field">
          <label for="inspector-folder-name">Name</label>
          <input
            id="inspector-folder-name"
            class="input"
            type="text"
            name="project_folder[name]"
            value={@record.name}
            required
            autocomplete="off"
            phx-debounce="300"
          />
        </div>
        <div class="field">
          <label for="inspector-folder-parent">Inside</label>
          <select id="inspector-folder-parent" class="input" name="project_folder[parent_id]">
            <option value="">Top level</option>
            <option
              :for={folder <- parent_options(@user, @record)}
              value={folder.id}
              selected={folder.id == @record.parent_id}
            >
              {folder.name}
            </option>
          </select>
        </div>
        <div class="field">
          <label for="inspector-folder-state">State</label>
          <select id="inspector-folder-state" class="input" name="project_folder[state]">
            <option
              :for={{label, value} <- folder_states()}
              value={value}
              selected={value == Atom.to_string(@record.state)}
            >
              {label}
            </option>
          </select>
        </div>
        <div class="actions">
          <.link navigate={~p"/folders/#{@record.id}"} class="open">Open folder</.link>
        </div>
      </form>
      <.meta record={@record} />
    </section>
    """
  end

  attr :record, :any, required: true

  defp meta(assigns) do
    ~H"""
    <dl class="meta">
      <div>
        <dt>Created</dt>
        <dd>{stamp(@record.inserted_at)}</dd>
      </div>
      <div>
        <dt>Updated</dt>
        <dd>{stamp(@record.updated_at)}</dd>
      </div>
    </dl>
    """
  end

  @impl true
  def handle_event("save", %{"task" => params}, socket) do
    save(socket, fn record -> save_task(socket.assigns.user, record, params) end)
  end

  def handle_event("save", %{"project" => params}, socket) do
    save(socket, fn record -> save_project(socket.assigns.user, record, params) end)
  end

  def handle_event("save", %{"project_folder" => params}, socket) do
    save(socket, fn record -> save_folder(socket.assigns.user, record, params) end)
  end

  defp save(socket, fun) do
    case fun.(socket.assigns.record) do
      {:ok, record} when record == socket.assigns.record ->
        {:noreply, socket}

      {:ok, record} ->
        send(self(), :inspector_saved)
        {:noreply, assign(socket, record: record, error: nil)}

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  defp save_task(user, task, params) do
    title = params["title"]
    notes = blank(params["notes"])
    project_id = blank(params["project_id"])
    inbox = inbox_checked?(params["inbox"])
    state = params["state"]

    with {:ok, task} <-
           maybe(task, renamed?(title, task.title), fn ->
             Tasks.rename_task(user, task.id, title, command())
           end),
         {:ok, task} <-
           maybe(task, notes != blank(task.notes), fn ->
             Tasks.set_notes(user, task.id, notes, command())
           end),
         {:ok, task} <-
           maybe(task, project_id != task.project_id, fn ->
             Tasks.file_task(user, task.id, project_id, command())
           end),
         {:ok, task} <-
           maybe(task, inbox != task.inbox, fn ->
             Tasks.set_inbox(user, task.id, inbox, command())
           end),
         {:ok, task} <-
           maybe(task, state not in [nil, Atom.to_string(task.state)], fn ->
             set_task_state(user, task, state)
           end) do
      {:ok, Tasks.get_task(user, task.id)}
    else
      {:error, _} -> {:error, "Could not save this task."}
    end
  end

  defp save_project(user, project, params) do
    title = params["title"]
    notes = blank(params["notes"])
    folder_id = blank(params["project_folder_id"])
    state = params["state"]

    with {:ok, project} <-
           maybe(project, renamed?(title, project.title), fn ->
             Projects.rename_project(user, project.id, title, command())
           end),
         {:ok, project} <-
           maybe(project, notes != blank(project.notes), fn ->
             Projects.set_notes(user, project.id, notes, command())
           end),
         {:ok, project} <-
           maybe(project, folder_id != project.project_folder_id, fn ->
             Projects.file_project(user, project.id, folder_id, command())
           end),
         {:ok, project} <-
           maybe(project, state not in [nil, Atom.to_string(project.state)], fn ->
             set_project_state(user, project, state)
           end) do
      {:ok, Projects.get_project(user, project.id)}
    else
      {:error, _} -> {:error, "Could not save this project."}
    end
  end

  defp save_folder(user, folder, params) do
    name = params["name"]
    parent_id = blank(params["parent_id"])
    state = params["state"]

    with {:ok, folder} <-
           maybe(folder, renamed?(name, folder.name), fn ->
             ProjectFolders.rename_folder(user, folder.id, name, command())
           end),
         {:ok, folder} <-
           maybe(folder, parent_id != folder.parent_id, fn ->
             ProjectFolders.reparent_folder(user, folder.id, parent_id, command())
           end),
         {:ok, folder} <-
           maybe(folder, state not in [nil, Atom.to_string(folder.state)], fn ->
             set_folder_state(user, folder, state)
           end) do
      {:ok, ProjectFolders.get_folder(user, folder.id)}
    else
      {:error, _} -> {:error, "Could not save this folder."}
    end
  end

  defp maybe(record, false, _fun), do: {:ok, record}
  defp maybe(_record, true, fun), do: fun.()

  # A cleared name is an edit in progress, not a rename to nothing.
  defp renamed?(incoming, current), do: incoming not in [nil, "", current]

  defp set_task_state(user, task, "done"), do: Tasks.complete_task(user, task.id, command())
  defp set_task_state(user, task, "dropped"), do: Tasks.drop_task(user, task.id, command())
  defp set_task_state(user, task, "to_do"), do: Tasks.reopen_task(user, task.id, command())
  defp set_task_state(_user, task, _state), do: {:ok, task}

  defp set_project_state(user, project, "done"),
    do: Projects.complete_project(user, project.id, command())

  defp set_project_state(user, project, "dropped"),
    do: Projects.drop_project(user, project.id, command())

  defp set_project_state(user, project, "to_do"),
    do: Projects.reopen_project(user, project.id, command())

  defp set_project_state(_user, project, _state), do: {:ok, project}

  defp set_folder_state(user, folder, "dropped"),
    do: ProjectFolders.drop_folder(user, folder.id, command())

  defp set_folder_state(user, folder, "active"),
    do: ProjectFolders.activate_folder(user, folder.id, command())

  defp set_folder_state(_user, folder, _state), do: {:ok, folder}

  defp load(_user, nil), do: nil
  defp load(user, %{type: :task, id: id}), do: Tasks.get_task(user, id)
  defp load(user, %{type: :project, id: id}), do: Projects.get_project(user, id)
  defp load(user, %{type: :folder, id: id}), do: ProjectFolders.get_folder(user, id)

  defp task_projects(user, task) do
    projects = Projects.list_open(user)

    if task.project_id && task.project_id not in Enum.map(projects, & &1.id) do
      case Projects.get_project(user, task.project_id) do
        nil -> projects
        project -> [project | projects]
      end
    else
      projects
    end
  end

  defp parent_options(user, folder) do
    folders = ProjectFolders.list_all(user)
    excluded = MapSet.new([folder.id | descendant_ids(folders, folder.id)])
    Enum.reject(folders, &MapSet.member?(excluded, &1.id))
  end

  defp descendant_ids(folders, id) do
    folders
    |> Enum.filter(&(&1.parent_id == id))
    |> Enum.flat_map(fn child -> [child.id | descendant_ids(folders, child.id)] end)
  end

  defp stamp(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  defp stamp(_), do: ""

  # A hidden "false" is always submitted. A checked box adds "true" after it.
  defp inbox_checked?(values) when is_list(values), do: "true" in Enum.map(values, &to_string/1)
  defp inbox_checked?(value), do: value in [true, "true"]

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(value), do: value

  defp command, do: Ecto.UUID.generate()
end
