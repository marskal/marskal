defmodule MarskalWeb.InspectorPanel do
  @moduledoc """
  The side panel for the open task, project, folder, or tag.
  """

  use MarskalWeb, :live_component

  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Tags
  alias Marskal.Tags.Tag
  alias Marskal.Tags.Tree
  alias Marskal.Tasks
  alias MarskalWeb.TagComponents

  defp task_states, do: [{"To-Do", "to_do"}, {"Done", "done"}, {"Dropped", "dropped"}]
  defp folder_states, do: [{"Active", "active"}, {"Dropped", "dropped"}]

  defp tag_states,
    do: [{"Active", "active"}, {"On hold", "on_hold"}, {"Dropped", "dropped"}]

  @impl true
  def update(assigns, socket) do
    stale? =
      socket.assigns[:loaded] != {assigns.selection, assigns[:change_version]} or
        socket.assigns[:user] != assigns.user

    socket = assign(socket, assigns)

    if stale? do
      {:ok, reload(socket)}
    else
      {:ok, socket}
    end
  end

  # Reloads on a new selection, and on every broadcast change, so an edit made
  # elsewhere shows here too. The select options are loaded once per reload,
  # not on every render.
  defp reload(socket) do
    %{user: user, selection: selection} = socket.assigns
    record = load(user, selection)
    error = if socket.assigns[:loaded_selection] == selection, do: socket.assigns[:error]

    picker =
      if socket.assigns[:loaded_selection] == selection,
        do: socket.assigns[:picker],
        else: %{query: "", results: []}

    socket
    |> assign(:record, record)
    |> assign(:options, options(user, record))
    |> assign(:tagging, tagging(user, record))
    |> assign(:outline, outline(user, record))
    |> assign(:picker, picker || %{query: "", results: []})
    |> assign(:error, error)
    |> assign(:loaded_selection, selection)
    |> assign(:loaded, {selection, socket.assigns[:change_version]})
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

        .hint {
          margin: 0;
          font-size: 0.8rem;
          color: var(--muted);
        }

        /* input.input matches app.css input[type="text"] on specificity, so the
           scoped rule wins. */
        .input,
        input.input {
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

        .picked {
          display: flex;
          flex-wrap: wrap;
          gap: 0.35rem;
          margin: 0;
          padding: 0;
          list-style: none;
          font-size: 0.85rem;
        }

        .picked li {
          display: inline-flex;
          align-items: center;
          gap: 0.2rem;
          padding: 0.1rem 0.2rem 0.1rem 0.55rem;
          border: 1px solid var(--border);
          border-radius: 999px;
        }

        .picked li.is-inherited {
          padding-right: 0.55rem;
          border-style: dashed;
          color: var(--muted);
        }

        .picked button {
          padding: 0 0.3rem;
          border: 0;
          background: transparent;
          color: var(--muted);
          line-height: 1.2;
        }

        .suggestions {
          margin: 0.35rem 0 0;
          padding: 0;
          list-style: none;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: var(--bg);
        }

        .suggestions li + li {
          border-top: 1px solid var(--border);
        }

        .suggestions button.suggestion {
          display: block;
          width: 100%;
          padding: 0.4rem 0.6rem;
          border: 0;
          border-radius: 0;
          background: transparent;
          color: var(--text);
          text-align: left;
        }

        .suggestions button.suggestion:is(:hover, :focus-visible) {
          background: color-mix(in srgb, var(--accent) 12%, var(--bg));
        }

        .create {
          display: flex;
          flex-wrap: wrap;
          gap: 0.4rem;
          align-items: center;
          padding: 0.4rem 0.6rem;
        }

        .create select {
          flex: 1 1 8rem;
        }

        .danger {
          margin-right: auto;
        }

        .dates {
          gap: 0.6rem;
        }

        .day-time {
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
        }

        .day-time__inputs {
          display: grid;
          grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
          gap: 0.4rem;
        }

        .indefinite,
        .field label.toggle,
        .toggle {
          display: flex;
          align-items: center;
          gap: 0.4rem;
          font-weight: 400;
          color: var(--text);
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
        Select a task, project, folder, or tag to edit.
      </p>
      <p :if={@selection && @record == nil} class="app-inspector__empty">
        That item is not available.
      </p>
      <.task_form
        :if={match?(%Tasks.Task{}, @record)}
        user={@user}
        change_version={assigns[:change_version]}
        zone={Marskal.Accounts.timezone(@user)}
        myself={@myself}
        record={@record}
        options={@options}
        error={@error}
        tagging={@tagging}
        picker={@picker}
        outline={@outline}
      />
      <.project_form
        :if={match?(%Projects.Project{}, @record)}
        zone={Marskal.Accounts.timezone(@user)}
        myself={@myself}
        record={@record}
        options={@options}
        error={@error}
        tagging={@tagging}
        picker={@picker}
      />
      <.folder_form
        :if={match?(%ProjectFolders.ProjectFolder{}, @record)}
        myself={@myself}
        record={@record}
        options={@options}
        error={@error}
      />
      <.tag_form
        :if={match?(%Tag{}, @record)}
        myself={@myself}
        record={@record}
        options={@options}
        error={@error}
      />
    </div>
    """
  end

  attr :myself, :any, required: true
  attr :record, :any, required: true
  attr :options, :list, default: []
  attr :error, :string, default: nil
  attr :tagging, :map, required: true
  attr :picker, :map, required: true
  attr :zone, :string, required: true

  attr :outline, :map,
    default: %{},
    doc: "the task's parent, the dates it goes by, and whether it is resolved from above"

  attr :user, :any, required: true
  attr :change_version, :any, default: nil

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
          <label for="inspector-task-url">URL</label>
          <input
            id="inspector-task-url"
            class="input"
            type="text"
            inputmode="url"
            name="task[url]"
            value={@record.url}
            placeholder="https://… or file://…"
            autocomplete="off"
            spellcheck="false"
            phx-debounce="300"
          />
          <MarskalWeb.UrlLink.link url={@record.url} text />
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
          <label for="inspector-task-location">Location</label>
          <MarskalWeb.TaskComponents.location_select
            id="inspector-task-location"
            class="input"
            name="task[location]"
            task={@record}
            projects={@options}
          />
          <p :if={@outline[:parent]} class="hint" id="inspector-task-parent">
            Subtask of {@outline[:parent].title}. Choosing another location moves it out.
          </p>
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
          <p :if={@outline[:resolved_above]} class="hint" id="inspector-task-resolved-above">
            Resolved along with the task or project above. Reopen that to bring this back.
          </p>
        </div>
        <div class="field">
          <label class="toggle">
            <input type="hidden" name="task[flagged]" value="false" />
            <input
              type="checkbox"
              id="inspector-task-flagged"
              name="task[flagged]"
              value="true"
              checked={@record.flagged}
            /> Flagged
          </label>
          <p
            :if={!@record.flagged and project_flagged?(@record, @options)}
            class="hint"
            id="inspector-task-flagged-by-project"
          >
            Flagged by its project.
          </p>
        </div>
        <MarskalWeb.DateFields.inputs
          form="task"
          id="inspector-task-dates"
          record={@record}
          zone={@zone}
          inherited={@outline[:dates]}
        />
        <div class="actions">
          <button
            type="button"
            id="inspector-task-delete"
            class="danger"
            phx-click="delete"
            phx-target={@myself}
            data-confirm={delete_task_confirm(@record)}
          >
            Delete
          </button>
          <.link navigate={~p"/tasks/#{@record.id}"} class="open">Open task</.link>
        </div>
      </form>
      <.live_component
        module={MarskalWeb.RepeatPanel}
        id="inspector-task-repeat"
        user={@user}
        task={@record}
        change_version={@change_version}
      />
      <.tag_picker id="inspector-task-tags" myself={@myself} tagging={@tagging} picker={@picker} />
      <.meta record={@record} zone={@zone} />
    </section>
    """
  end

  attr :myself, :any, required: true
  attr :record, :any, required: true
  attr :options, :list, default: []
  attr :error, :string, default: nil
  attr :tagging, :map, required: true
  attr :picker, :map, required: true
  attr :zone, :string, required: true

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
          <label for="inspector-project-url">URL</label>
          <input
            id="inspector-project-url"
            class="input"
            type="text"
            inputmode="url"
            name="project[url]"
            value={@record.url}
            placeholder="https://… or file://…"
            autocomplete="off"
            spellcheck="false"
            phx-debounce="300"
          />
          <MarskalWeb.UrlLink.link url={@record.url} text />
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
              :for={folder <- @options}
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
        <label class="toggle">
          <input type="hidden" name="project[flagged]" value="false" />
          <input
            type="checkbox"
            id="inspector-project-flagged"
            name="project[flagged]"
            value="true"
            checked={@record.flagged}
          /> Flagged
        </label>
        <MarskalWeb.DateFields.inputs
          form="project"
          id="inspector-project-dates"
          record={@record}
          zone={@zone}
        />
        <div class="actions">
          <button
            type="button"
            id="inspector-project-delete"
            class="danger"
            phx-click="delete"
            phx-target={@myself}
            data-confirm="Delete this project and every task in it? To finish it or give it up, use Done or Dropped."
          >
            Delete
          </button>
          <.link navigate={~p"/projects/#{@record.id}"} class="open">Open project</.link>
        </div>
      </form>
      <.tag_picker id="inspector-project-tags" myself={@myself} tagging={@tagging} picker={@picker} />
      <.meta record={@record} zone={@zone} />
    </section>
    """
  end

  attr :myself, :any, required: true
  attr :record, :any, required: true
  attr :options, :list, default: []
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
              :for={folder <- @options}
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
      </form>
      <.meta record={@record} />
    </section>
    """
  end

  attr :myself, :any, required: true
  attr :record, :any, required: true
  attr :options, :list, default: []
  attr :error, :string, default: nil

  defp tag_form(assigns) do
    ~H"""
    <section class="inspector-form" data-inspect-type="tag" data-inspect-id={@record.id}>
      <p :if={@error} class="errors" role="alert">{@error}</p>
      <form id="inspector-tag" class="form" phx-change="save" phx-submit="save" phx-target={@myself}>
        <div class="field">
          <label for="inspector-tag-name">Name</label>
          <input
            id="inspector-tag-name"
            class="input"
            type="text"
            name="tag[name]"
            value={@record.name}
            required
            autocomplete="off"
            phx-debounce="300"
          />
        </div>
        <div class="field">
          <label for="inspector-tag-parent">Inside</label>
          <select id="inspector-tag-parent" class="input" name="tag[parent_id]">
            <option value="">Top level</option>
            <option :for={tag <- @options} value={tag.id} selected={tag.id == @record.parent_id}>
              {TagComponents.path_text(tag)}
            </option>
          </select>
        </div>
        <div class="field">
          <label for="inspector-tag-state">State</label>
          <select id="inspector-tag-state" class="input" name="tag[state]">
            <option
              :for={{label, value} <- tag_states()}
              value={value}
              selected={value == Atom.to_string(@record.state)}
            >
              {label}
            </option>
          </select>
          <p class="hint">
            On hold makes its tasks unavailable. Dropped hides it and the tags inside.
          </p>
        </div>
        <div class="actions">
          <button
            type="button"
            id="inspector-tag-delete"
            class="danger"
            phx-click="tag-delete"
            phx-target={@myself}
            data-confirm="Delete this tag and the tags inside it? Tasks keep everything else."
          >
            Delete
          </button>
          <.link navigate={~p"/tags/#{@record.id}"} class="open">Open tag</.link>
        </div>
      </form>
      <.meta record={@record} />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :myself, :any, required: true
  attr :tagging, :map, required: true
  attr :picker, :map, required: true

  # Tags on a task or project (ADR 0005). Enter adds the first suggestion;
  # Create makes a tag with the typed text as its name, under the chosen
  # parent.
  defp tag_picker(assigns) do
    ~H"""
    <div class="field" id={@id}>
      <label for={"#{@id}-query"}>Tags</label>
      <ul :if={@tagging.direct != [] or @tagging.inherited != []} class="picked">
        <li :for={tag <- @tagging.direct} data-tag-id={tag.id}>
          <TagComponents.path tag={tag} />
          <button
            type="button"
            phx-click="tag-remove"
            phx-value-id={tag.id}
            phx-target={@myself}
            aria-label={"Remove #{TagComponents.path_text(tag)}"}
          >
            ×
          </button>
        </li>
        <li
          :for={tag <- @tagging.inherited}
          class="is-inherited"
          data-tag-id={tag.id}
          title="From the project"
        >
          <TagComponents.path tag={tag} />
        </li>
      </ul>
      <form id={"#{@id}-picker"} phx-change="tag-search" phx-submit="tag-pick" phx-target={@myself}>
        <input
          id={"#{@id}-query"}
          class="input"
          type="text"
          name="tag_query"
          value={@picker.query}
          placeholder="Add a tag…"
          autocomplete="off"
          phx-debounce="150"
        />
        <ul :if={String.trim(@picker.query) != ""} class="suggestions">
          <li :for={tag <- @picker.results}>
            <button
              type="button"
              class="suggestion"
              phx-click="tag-add"
              phx-value-id={tag.id}
              phx-target={@myself}
            >
              <TagComponents.path tag={tag} />
            </button>
          </li>
          <li class="create">
            <select name="tag_parent" class="input" aria-label="Create inside">
              <option value="">Top level</option>
              <option :for={tag <- @tagging.parents} value={tag.id}>
                {TagComponents.path_text(tag)}
              </option>
            </select>
            <button type="submit" name="action" value="create">
              Create “{String.trim(@picker.query)}”
            </button>
          </li>
        </ul>
      </form>
    </div>
    """
  end

  attr :record, :any, required: true
  attr :zone, :string, default: "Europe/Copenhagen"

  defp meta(assigns) do
    ~H"""
    <dl class="meta">
      <div>
        <dt>Created</dt>
        <dd>{stamp(@record.inserted_at, @zone)}</dd>
      </div>
      <div>
        <dt>Updated</dt>
        <dd>{stamp(@record.updated_at, @zone)}</dd>
      </div>
      <div :if={Map.get(@record, :resolved_at)}>
        <dt>First resolved</dt>
        <dd>{stamp(@record.resolved_at, @zone)}</dd>
      </div>
    </dl>
    """
  end

  @impl true
  def handle_event("save", %{"task" => params}, socket) do
    attrs =
      params
      |> Map.take(["title", "notes", "url", "flagged", "state"])
      |> Map.merge(location_params(params))
      |> Map.reject(fn {_key, value} -> value == nil end)
      |> Map.merge(date_params(params, socket))

    save(socket, &Tasks.update_task(&1, &2, drop_blank_title(attrs, "title"), &3))
  end

  def handle_event("save", %{"project" => params}, socket) do
    attrs =
      params
      |> Map.take(["title", "notes", "url", "flagged", "project_folder_id", "state"])
      |> Map.merge(date_params(params, socket))

    save(socket, &Projects.update_project(&1, &2, drop_blank_title(attrs, "title"), &3))
  end

  def handle_event("save", %{"project_folder" => params}, socket) do
    attrs = Map.take(params, ["name", "parent_id", "state"])
    save(socket, &ProjectFolders.update_folder(&1, &2, drop_blank_title(attrs, "name"), &3))
  end

  def handle_event("save", %{"tag" => params}, socket) do
    attrs = Map.take(params, ["name", "parent_id", "state"])
    save(socket, &Tags.update_tag(&1, &2, drop_blank_title(attrs, "name"), &3))
  end

  def handle_event("delete", _params, socket) do
    %{user: user, record: record} = socket.assigns

    result =
      case record do
        %Tasks.Task{} -> Tasks.delete_task(user, record.id, Ecto.UUID.generate())
        %Projects.Project{} -> Projects.delete_project(user, record.id, Ecto.UUID.generate())
      end

    case result do
      {:ok, _} -> {:noreply, assign(socket, record: nil, error: nil)}
      {:error, _} -> {:noreply, assign(socket, :error, "Could not delete.")}
    end
  end

  def handle_event("tag-delete", _params, socket) do
    %{user: user, record: record} = socket.assigns

    case Tags.delete_tag(user, record.id, Ecto.UUID.generate()) do
      {:ok, _} -> {:noreply, assign(socket, record: nil, error: nil)}
      {:error, _} -> {:noreply, assign(socket, :error, "Could not delete the tag.")}
    end
  end

  def handle_event("tag-search", %{"tag_query" => query}, socket) do
    {:noreply, assign(socket, :picker, %{query: query, results: suggestions(socket, query)})}
  end

  def handle_event("tag-add", %{"id" => tag_id}, socket), do: link_tag(socket, :tag, tag_id)
  def handle_event("tag-remove", %{"id" => tag_id}, socket), do: link_tag(socket, :untag, tag_id)

  def handle_event("tag-pick", %{"tag_query" => query} = params, socket) do
    case {params["action"], socket.assigns.picker.results} do
      {"create", _} -> create_and_link(socket, query, params["tag_parent"])
      {_, [first | _]} -> link_tag(socket, :tag, first.id)
      {_, []} -> create_and_link(socket, query, params["tag_parent"])
    end
  end

  # Each save is one command carrying only the fields that differ. The form
  # posts its whole state, so a resent event changes nothing and needs no
  # client-side command id.
  defp save(socket, update) do
    %{user: user, record: record} = socket.assigns

    case update.(user, record.id, Ecto.UUID.generate()) do
      {:ok, record} ->
        {:noreply, assign(socket, record: record, error: nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :error, error_message(changeset))}

      {:error, :not_found} ->
        {:noreply, assign(socket, :error, "That item is not available.")}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Could not save.")}
    end
  end

  # A cleared name is an edit in progress, not a rename to nothing.
  defp drop_blank_title(attrs, key) do
    case attrs do
      %{^key => value} when is_binary(value) ->
        if String.trim(value) == "", do: Map.delete(attrs, key), else: attrs

      _ ->
        attrs
    end
  end

  defp error_message(changeset) do
    {field, error} = hd(changeset.errors)
    "#{field_label(field)} #{translate_error(error)}."
  end

  defp field_label(:url), do: "URL"
  defp field_label(field), do: Phoenix.Naming.humanize(field)

  defp suggestions(socket, query) do
    %{tree: tree, direct: direct} = socket.assigns.tagging
    taken = MapSet.new(direct, & &1.id)
    tree |> Tags.search(query) |> Enum.reject(&MapSet.member?(taken, &1.id))
  end

  defp link_tag(socket, action, tag_id) do
    %{user: user, record: record} = socket.assigns

    result =
      case {record, action} do
        {%Tasks.Task{}, :tag} ->
          Tags.tag_task(user, record.id, tag_id, Ecto.UUID.generate())

        {%Tasks.Task{}, :untag} ->
          Tags.untag_task(user, record.id, tag_id, Ecto.UUID.generate())

        {%Projects.Project{}, :tag} ->
          Tags.tag_project(user, record.id, tag_id, Ecto.UUID.generate())

        {%Projects.Project{}, :untag} ->
          Tags.untag_project(user, record.id, tag_id, Ecto.UUID.generate())
      end

    case result do
      {:ok, _link} ->
        {:noreply,
         assign(socket,
           tagging: tagging(user, record),
           picker: %{query: "", results: []},
           error: nil
         )}

      {:error, _} ->
        {:noreply, assign(socket, :error, "Could not change the tags.")}
    end
  end

  defp create_and_link(socket, query, parent_id) do
    attrs = %{
      "name" => query,
      "parent_id" => if(parent_id in [nil, ""], do: nil, else: parent_id)
    }

    case Tags.create_tag(socket.assigns.user, attrs, Ecto.UUID.generate()) do
      {:ok, tag} ->
        link_tag(socket, :tag, tag.id)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :error, error_message(changeset))}

      {:error, _} ->
        {:noreply, assign(socket, :error, "Could not create the tag.")}
    end
  end

  # What the tag picker needs: the record's own tags, those it gets from its
  # project, the visible tags to create under, and the tree for search.
  defp tagging(user, %Tasks.Task{} = task) do
    tree = Tags.tree(user)
    [entries] = Map.values(Tags.effective_tags(user, [task], tree))

    %{
      tree: tree,
      direct: for(%{tag: tag, inherited: false} <- entries, do: tag),
      inherited: for(%{tag: tag, inherited: true} <- entries, do: tag),
      parents: visible_tags(tree)
    }
  end

  defp tagging(user, %Projects.Project{} = project) do
    tree = Tags.tree(user)

    %{
      tree: tree,
      direct: Tags.project_tags(user, project, tree),
      inherited: [],
      parents: visible_tags(tree)
    }
  end

  defp tagging(_user, _record), do: nil

  defp visible_tags(tree), do: tree |> Tree.all() |> Enum.filter(&Tree.visible?(tree, &1.id))

  # Where a task sits: its parent, the dates it goes by, and whether a task
  # or project above has resolved it (ADR 0006, ADR 0009).
  defp outline(user, %Tasks.Task{} = task) do
    %{
      parent: task.parent_id && Tasks.get_task(user, task.parent_id),
      dates: Tasks.effective_dates(user, [task])[task.id],
      resolved_above:
        task.state == :to_do and MapSet.member?(Tasks.resolved_ids(user, [task.id]), task.id)
    }
  end

  defp outline(_user, _record), do: %{}

  defp load(_user, nil), do: nil
  defp load(user, %{type: :task, id: id}), do: Tasks.get_task(user, id)
  defp load(user, %{type: :project, id: id}), do: Projects.get_project(user, id)
  defp load(user, %{type: :folder, id: id}), do: ProjectFolders.get_folder(user, id)
  defp load(user, %{type: :tag, id: id}), do: Tags.get_tag(user, id)

  defp options(user, %Tasks.Task{} = task), do: task_projects(user, task)
  defp options(user, %Projects.Project{}), do: ProjectFolders.list_all(user)
  defp options(user, %ProjectFolders.ProjectFolder{} = folder), do: parent_options(user, folder)

  # A tag can move anywhere visible except into its own subtree.
  defp options(user, %Tag{} = tag) do
    tree = Tags.tree(user)
    excluded = MapSet.new(Tree.subtree_ids(tree, tag.id))
    tree |> visible_tags() |> Enum.reject(&MapSet.member?(excluded, &1.id))
  end

  defp options(_user, nil), do: []

  defp project_flagged?(task, projects),
    do: Enum.any?(projects, &(&1.id == task.project_id and &1.flagged))

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

  defp stamp(%DateTime{} = datetime, zone),
    do: datetime |> DateTime.shift_zone!(zone) |> Calendar.strftime("%Y-%m-%d %H:%M")

  defp stamp(_datetime, _zone), do: ""

  # Deleting the open occurrence of a series ends the series (ADR 0007).
  defp delete_task_confirm(%Tasks.Task{series_id: id, state: :to_do}) when is_binary(id),
    do: "Delete this task and end its repeat? To skip only this one, use Dropped."

  defp delete_task_confirm(_task),
    do: "Delete this task? To finish it or give it up, use Done or Dropped."

  # A hidden "false" is always submitted. A checked box adds "true" after it.
  defp location_params(%{"location" => value}) do
    value
    |> MarskalWeb.TaskComponents.parse_location()
    |> Tasks.location_attrs()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp location_params(_params), do: %{}

  # The date inputs are only on the task and project forms. A post from
  # elsewhere, without them, leaves the dates alone.
  defp date_params(%{"due_date" => _} = params, socket) do
    %{user: user, record: record} = socket.assigns
    MarskalWeb.DateFields.params_to_attrs(params, record, Marskal.Accounts.timezone(user))
  end

  defp date_params(_params, _socket), do: %{}
end
