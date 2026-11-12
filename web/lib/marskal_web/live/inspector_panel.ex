defmodule MarskalWeb.InspectorPanel do
  @moduledoc """
  The side panel for the open task, project, folder, or tag.
  """

  use MarskalWeb, :live_component

  alias Marskal.GoTo
  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Tags
  alias Marskal.Tags.Tag
  alias Marskal.Tags.Tree
  alias Marskal.Tasks
  alias MarskalWeb.TagComponents

  defp task_states, do: [{"To-Do", "to_do"}, {"Done", "done"}, {"Dropped", "dropped"}]
  defp folder_states, do: [{"Active", "active"}, {"Dropped", "dropped"}]

  @date_texts %{"defer_text" => "defer", "planned_text" => "planned", "due_text" => "due"}

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
    same? = socket.assigns[:loaded_selection] == selection
    error = if same?, do: socket.assigns[:error]

    picker =
      if socket.assigns[:loaded_selection] == selection,
        do: socket.assigns[:picker],
        else: empty_picker()

    socket
    |> assign(:record, record)
    |> assign(:options, options(user, record))
    |> assign(:tagging, tagging(user, record))
    |> assign(:outline, outline(user, record))
    |> assign(:picker, picker || empty_picker())
    |> assign(:place, if(same?, do: socket.assigns[:place]))
    |> assign(:date_previews, if(same?, do: socket.assigns[:date_previews] || %{}, else: %{}))
    |> assign(:calendar, if(same?, do: socket.assigns[:calendar]))
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

        .field-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
        }

        .expand {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 1.75rem;
          height: 1.75rem;
          margin: -0.3rem 0;
          padding: 0;
          border: 0;
          background: transparent;
          color: var(--muted);
        }

        .expand:is(:hover, :focus-visible) {
          color: var(--text);
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
          border: 1px solid var(--border-strong);
          border-radius: 6px;
          background: var(--bg);
          color: var(--text);
          font: inherit;
        }

        textarea.input {
          resize: vertical;
          /* Four lines, plus this field's padding and border. Drag to grow it. */
          min-height: calc(4 * 1.45em + 0.9rem + 2px);
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

        .locations {
          max-height: 18rem;
          overflow-y: auto;
        }

        .locations button.suggestion {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }

        .locations [aria-selected="true"] > button.suggestion {
          background: color-mix(in srgb, var(--accent) 12%, var(--bg));
        }

        .locations .icon {
          flex-shrink: 0;
          color: var(--muted);
        }

        .locations .path {
          display: inline-flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: 0 0.3em;
          min-width: 0;
        }

        .locations :is(.ancestor, .sep),
        .locations .is-hidden .name {
          color: var(--muted);
        }

        .locations .current {
          margin-left: auto;
        }

        .locations .empty {
          padding: 0.4rem 0.6rem;
          color: var(--muted);
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

        .day-time {
          position: relative;
        }

        .day-time__label {
          display: flex;
          align-items: center;
          gap: 0.4rem;
        }

        .day-time__entry {
          display: flex;
          gap: 0.4rem;
        }

        .day-time__entry .input {
          flex: 1 1 auto;
          min-width: 0;
        }

        .day-time__pick {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          flex: 0 0 auto;
          width: 2.25rem;
          padding: 0;
        }

        .calendar {
          position: absolute;
          top: 100%;
          right: 0;
          z-index: 10;
          margin-top: 0.25rem;
          padding: 0.5rem;
          border: 1px solid var(--border);
          border-radius: 8px;
          background: var(--surface);
          box-shadow: 0 6px 24px var(--shadow);
        }

        .calendar__head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
          margin-bottom: 0.35rem;
        }

        .calendar__head button {
          display: inline-flex;
          padding: 0.25rem;
          border: 0;
          background: transparent;
          color: var(--muted);
        }

        .calendar__head button:is(:hover, :focus-visible) {
          color: var(--text);
        }

        .calendar__month {
          margin: 0;
          font-weight: 600;
          font-size: 0.9rem;
        }

        .calendar__grid {
          border-collapse: collapse;
          font-size: 0.85rem;
        }

        .calendar__grid th {
          padding: 0.2rem 0;
          font-weight: 400;
          font-size: 0.75rem;
          color: var(--muted);
        }

        .calendar__grid td {
          padding: 1px;
        }

        .calendar__day {
          width: 2rem;
          height: 2rem;
          padding: 0;
          border: 1px solid transparent;
          border-radius: 6px;
          background: transparent;
          color: var(--text);
          font-variant-numeric: tabular-nums;
        }

        .calendar__day:hover {
          background: var(--accent-tint);
        }

        .calendar__day--outside {
          color: var(--muted);
        }

        .calendar__day--today {
          border-color: var(--accent);
        }

        .calendar__day--selected {
          background: var(--accent);
          color: var(--accent-contrast);
        }

        .reads:empty {
          display: none;
        }

        .reads--error {
          color: var(--danger);
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
        place={@place}
        outline={@outline}
        date_previews={@date_previews}
        calendar={@calendar}
      />
      <.project_form
        :if={match?(%Projects.Project{}, @record)}
        user={@user}
        change_version={assigns[:change_version]}
        zone={Marskal.Accounts.timezone(@user)}
        myself={@myself}
        record={@record}
        options={@options}
        error={@error}
        tagging={@tagging}
        picker={@picker}
        date_previews={@date_previews}
        calendar={@calendar}
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

  attr :date_previews, :map, default: %{}
  attr :calendar, :map, default: nil
  attr :place, :map, default: nil

  attr :user, :any, required: true
  attr :change_version, :any, default: nil

  defp task_form(assigns) do
    ~H"""
    <section class="inspector-form" data-inspect-type="task" data-inspect-id={@record.id}>
      <p :if={@error} class="errors" role="alert">{@error}</p>
      <form
        id="inspector-task"
        class="form"
        phx-change="save"
        data-autosave
        phx-submit="save"
        phx-target={@myself}
      >
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
        <.notes_field form="task" record={@record} placeholder="Markdown is fine…" />
        <.location_picker
          id="inspector-task-location"
          myself={@myself}
          task={@record}
          projects={@options}
          place={@place}
          parent={@outline[:parent]}
        />
        <.tag_picker id="inspector-task-tags" myself={@myself} tagging={@tagging} picker={@picker} />
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
          target={@myself}
          previews={@date_previews}
          calendar={@calendar}
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
        </div>
      </form>
      <.notes_dialog form="task" myself={@myself} record={@record} />
      <.live_component
        module={MarskalWeb.RepeatPanel}
        id="inspector-task-repeat"
        user={@user}
        record={@record}
        change_version={@change_version}
      />
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
  attr :user, :any, required: true
  attr :change_version, :any, default: nil
  attr :date_previews, :map, default: %{}
  attr :calendar, :map, default: nil

  defp project_form(assigns) do
    ~H"""
    <section class="inspector-form" data-inspect-type="project" data-inspect-id={@record.id}>
      <p :if={@error} class="errors" role="alert">{@error}</p>
      <form
        id="inspector-project"
        class="form"
        phx-change="save"
        data-autosave
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
        <.notes_field
          form="project"
          record={@record}
          placeholder="What does done look like? Markdown is fine."
        />
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
        <.tag_picker
          id="inspector-project-tags"
          myself={@myself}
          tagging={@tagging}
          picker={@picker}
        />
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
          target={@myself}
          previews={@date_previews}
          calendar={@calendar}
        />
        <div class="actions">
          <button
            type="button"
            id="inspector-project-delete"
            class="danger"
            phx-click="delete"
            phx-target={@myself}
            data-confirm={delete_project_confirm(@record)}
          >
            Delete
          </button>
          <.link navigate={~p"/projects/#{@record.id}"} class="open">Open project</.link>
        </div>
      </form>
      <.notes_dialog form="project" myself={@myself} record={@record} />
      <.live_component
        module={MarskalWeb.RepeatPanel}
        id="inspector-project-repeat"
        user={@user}
        record={@record}
        change_version={@change_version}
      />
      <.live_component
        module={MarskalWeb.ReviewPanel}
        id="inspector-project-review"
        user={@user}
        record={@record}
        change_version={@change_version}
      />
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
        data-autosave
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
      <form
        id="inspector-tag"
        class="form"
        phx-change="save"
        data-autosave
        phx-submit="save"
        phx-target={@myself}
      >
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
  attr :task, Tasks.Task, required: true
  attr :projects, :list, required: true, doc: "the open projects, and the task's own"

  attr :place, :map,
    required: true,
    doc: "the open list: targets, query, and results; nil when closed"

  attr :parent, :any, default: nil

  # Where a task lives (ADR 0017), picked as in Go to (ADR 0033): focus
  # lists every location, typing narrows them by name or folder path, and
  # choosing one moves the task. The field is in the task form, but has its
  # own change event, so a query is never saved.
  defp location_picker(assigns) do
    assigns = assign(assigns, :current, location_text(assigns.task, assigns.projects))

    ~H"""
    <div
      class="field location"
      id={"#{@id}-field"}
      phx-hook=".LocationPicker"
      phx-target={@myself}
      data-current={@current}
    >
      <label for={@id}>{gettext("Location")}</label>
      <input
        id={@id}
        class="input"
        type="text"
        name="location_query"
        value={@current}
        placeholder={@current}
        role="combobox"
        aria-expanded={to_string(@place != nil)}
        aria-controls={"#{@id}-results"}
        aria-autocomplete="list"
        autocomplete="off"
        autocapitalize="off"
        spellcheck="false"
        phx-change="location-search"
        phx-target={@myself}
      />
      <ul
        :if={@place}
        id={"#{@id}-results"}
        class="suggestions locations"
        role="listbox"
        aria-label={gettext("Locations")}
      >
        <li
          :for={target <- @place.results}
          id={"#{@id}-#{target.type}-#{target.id}"}
          role="option"
          class={target.hidden && "is-hidden"}
          data-current={location_value(target) == location_value(@task) && "true"}
        >
          <button
            type="button"
            class="suggestion"
            tabindex="-1"
            phx-click="location-pick"
            phx-value-location={location_value(target)}
            phx-target={@myself}
          >
            <.location_icon target={target} />
            <span class="path">
              <%= for segment <- Enum.drop(target.path, -1) do %>
                <span class="ancestor">{segment}</span>
                <span class="sep" aria-hidden="true">›</span>
              <% end %>
              <span class="name">{List.last(target.path)}</span>
            </span>
            <Lucideicons.check
              :if={location_value(target) == location_value(@task)}
              class="icon current"
              aria-label={gettext("Current location")}
            />
          </button>
        </li>
        <li :if={@place.results == []} class="empty">{gettext("Nothing matches.")}</li>
      </ul>
      <p :if={@parent} class="hint" id="inspector-task-parent">
        {gettext("Subtask of %{title}. Choosing another location moves it out.",
          title: @parent.title
        )}
      </p>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".LocationPicker" extension="ts">
        import {ViewHook} from "phoenix_live_view"

        // A combobox, as Go to is: focus stays in the field, the arrow keys
        // move the selected option, and Enter picks it. Opening empties the
        // field, leaving the current location as its placeholder; Escape, or
        // leaving the field, closes the list and puts it back.
        export default class extends ViewHook {
          active: string | null = null
          wasOpen = false

          get input() { return this.el.querySelector<HTMLInputElement>("input")! }
          get list() { return this.el.querySelector<HTMLElement>("[role=listbox]") }
          get options() { return Array.from(this.el.querySelectorAll<HTMLElement>("[role=option]")) }

          onFocus = () => this.open()

          // A click in the field after Escape opens the list again.
          onClick = () => { if (!this.list) this.open() }

          // A new query selects its best match.
          onInput = () => { this.active = null }

          onKeydown = (event: KeyboardEvent) => {
            if (event.key === "ArrowDown" || event.key === "ArrowUp") {
              event.preventDefault()
              if (!this.list) return this.open()
              const options = this.options
              const index = options.findIndex((option) => option.id === this.active)
              const step = event.key === "ArrowDown" ? 1 : -1
              const next = options[(index + step + options.length) % options.length]
              if (next) this.select(next)
            } else if (event.key === "Enter") {
              // The field is in the task form; Enter must not submit it.
              event.preventDefault()
              const option = this.active ? document.getElementById(this.active) : null
              option?.querySelector("button")?.click()
            } else if (event.key === "Escape" && this.list) {
              event.preventDefault()
              event.stopPropagation()
              this.close()
              this.input.select()
            }
          }

          // Keeps focus in the field, so a click on an option is not a blur.
          onPointerDown = (event: PointerEvent) => {
            if ((event.target as Element).closest("[role=listbox]")) event.preventDefault()
          }

          onPointerMove = (event: PointerEvent) => {
            const option = (event.target as Element).closest<HTMLElement>("[role=option]")
            if (option && option.id !== this.active) this.select(option)
          }

          mounted() {
            this.input.addEventListener("focus", this.onFocus)
            this.input.addEventListener("click", this.onClick)
            this.input.addEventListener("blur", () => this.close())
            this.input.addEventListener("input", this.onInput)
            this.input.addEventListener("keydown", this.onKeydown)
            this.el.addEventListener("pointerdown", this.onPointerDown)
            this.el.addEventListener("pointermove", this.onPointerMove)
          }

          // Opening selects the current location; a narrower list keeps the
          // selected option if it is still there. A list that closes, on a
          // pick, shows the location the task now has.
          updated() {
            const options = this.options
            const kept = options.find((option) => option.id === this.active)
            const current = this.active === null && this.input.value === ""
              ? options.find((option) => option.dataset.current === "true")
              : undefined
            this.select(kept ?? current ?? options[0] ?? null)
            if (this.wasOpen && !this.list) this.input.value = this.el.dataset.current ?? ""
            this.wasOpen = Boolean(this.list)
          }

          open() {
            this.input.value = ""
            this.active = null
            this.pushEventTo(this.el, "location-open", {})
          }

          close() {
            this.input.value = this.el.dataset.current ?? ""
            this.select(null)
            if (this.list) this.pushEventTo(this.el, "location-close", {})
          }

          select(option: HTMLElement | null) {
            this.active = option?.id ?? null
            for (const each of this.options) each.setAttribute("aria-selected", String(each === option))
            if (option) {
              this.input.setAttribute("aria-activedescendant", option.id)
              option.scrollIntoView({block: "nearest"})
            } else {
              this.input.removeAttribute("aria-activedescendant")
            }
          }
        }
      </script>
    </div>
    """
  end

  attr :target, GoTo.Target, required: true

  defp location_icon(%{target: %{type: :view, id: :inbox}} = assigns),
    do: ~H|<Lucideicons.inbox class="icon" />|

  defp location_icon(%{target: %{type: :view, id: :none}} = assigns),
    do: ~H|<Lucideicons.list class="icon" />|

  defp location_icon(%{target: %{state: :done}} = assigns),
    do: ~H|<Lucideicons.circle_check_big class="icon" />|

  defp location_icon(%{target: %{state: :dropped}} = assigns),
    do: ~H|<Lucideicons.circle_off class="icon" />|

  defp location_icon(assigns), do: ~H|<Lucideicons.circle class="icon" />|

  attr :id, :string, required: true
  attr :myself, :any, required: true
  attr :tagging, :map, required: true
  attr :picker, :map, required: true

  # Tags on a task or project (ADR 0005), inside the task or project form.
  # Search and the parent menu have their own change events, so neither saves
  # the task. Enter adds the first suggestion, or creates one when nothing
  # matches. Create uses the typed name under the chosen parent.
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
      <div id={"#{@id}-picker"} phx-hook=".TagQuery" phx-target={@myself}>
        <input
          id={"#{@id}-query"}
          class="input"
          type="text"
          name="tag_query"
          value={@picker.query}
          placeholder="Add a tag…"
          autocomplete="off"
          phx-change="tag-search"
          phx-debounce="150"
          phx-target={@myself}
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
            <select
              id={"#{@id}-parent"}
              name="tag_parent"
              class="input"
              aria-label="Create inside"
              phx-change="tag-parent"
              phx-target={@myself}
            >
              <option value="" selected={@picker.parent == ""}>Top level</option>
              <option
                :for={tag <- @tagging.parents}
                value={tag.id}
                selected={tag.id == @picker.parent}
              >
                {TagComponents.path_text(tag)}
              </option>
            </select>
            <button
              type="button"
              phx-click="tag-pick"
              phx-value-action="create"
              phx-target={@myself}
            >
              Create “{String.trim(@picker.query)}”
            </button>
          </li>
        </ul>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".TagQuery" extension="ts">
          import {ViewHook} from "phoenix_live_view"

          // Enter reads the typed name and the parent menu now, rather than
          // waiting for the debounced search, and does not submit the task.
          export default class extends ViewHook<HTMLElement> {
            mounted() {
              this.el.addEventListener("keydown", (event: KeyboardEvent) => {
                if (event.key !== "Enter" || event.isComposing) return
                const query = this.el.querySelector("input")
                if (!(query instanceof HTMLInputElement) || event.target !== query) return
                event.preventDefault()
                const select = this.el.querySelector("select")
                this.pushEventTo(this.el, "tag-pick", {
                  tag_query: query.value,
                  tag_parent: select instanceof HTMLSelectElement ? select.value : ""
                })
              })
            }
          }
        </script>
      </div>
    </div>
    """
  end

  attr :form, :string, required: true, doc: ~s(the form's param name, "task" or "project")
  attr :record, :any, required: true
  attr :placeholder, :string, required: true

  defp notes_field(assigns) do
    ~H"""
    <div class="field">
      <div class="field-head">
        <label for={"inspector-#{@form}-notes"}>Notes</label>
        <button
          type="button"
          id={"inspector-#{@form}-notes-expand"}
          class="expand"
          commandfor={"inspector-#{@form}-notes-dialog"}
          command="show-modal"
          aria-label="Edit notes in a larger window"
          title="Edit notes in a larger window"
        >
          <Lucideicons.maximize_2 class="icon" />
        </button>
      </div>
      <textarea
        id={"inspector-#{@form}-notes"}
        class="input"
        name={"#{@form}[notes]"}
        rows="4"
        placeholder={@placeholder}
        phx-debounce="300"
      >{@record.notes}</textarea>
    </div>
    """
  end

  attr :form, :string, required: true, doc: ~s(the form's param name, "task" or "project")
  attr :myself, :any, required: true
  attr :record, :any, required: true

  # The notes again, with the whole window to write in and the rendered
  # Markdown beside them. The dialog has its own form, outside the
  # inspector's, so the notes are not posted twice; the hook carries the text
  # across as it opens and closes. Preview and Wrap are the viewer's choice,
  # kept in the browser.
  defp notes_dialog(assigns) do
    ~H"""
    <dialog
      id={"inspector-#{@form}-notes-dialog"}
      class="notes-dialog"
      phx-hook=".NotesDialog"
      phx-mounted={JS.ignore_attributes(["open", "data-preview", "data-wrap"])}
      data-inline={"inspector-#{@form}-notes"}
      data-preview="true"
      data-wrap="true"
      aria-labelledby={"inspector-#{@form}-notes-dialog-title"}
    >
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.notes-dialog) {
          :scope {
            width: calc(100vw - 2rem);
            max-width: none;
            height: calc(100dvh - 2rem);
            max-height: none;
            padding: 0;
            border: 1px solid var(--border);
            border-radius: 12px;
            background: var(--bg);
            color: var(--text);
          }

          :scope[open] {
            display: flex;
            flex-direction: column;
          }

          :scope::backdrop {
            background: var(--scrim);
          }

          header {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.5rem 0.5rem 0.5rem 1.1rem;
            border-bottom: 1px solid var(--border);
          }

          h2 {
            flex: 1;
            min-width: 0;
            margin: 0;
            overflow: hidden;
            font-size: 1rem;
            text-overflow: ellipsis;
            white-space: nowrap;
          }

          .toggle {
            display: inline-flex;
            align-items: center;
            gap: 0.35rem;
            padding: 0.3rem 0.6rem;
            border-color: var(--border);
            background: transparent;
            color: var(--muted);
            font-size: 0.85rem;
          }

          .toggle[aria-pressed="true"] {
            border-color: var(--border-strong);
            background: var(--surface);
            color: var(--text);
          }

          .close {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 2.25rem;
            height: 2.25rem;
            padding: 0;
            border: 0;
            background: transparent;
            color: var(--muted);
          }

          form {
            flex: 1;
            min-height: 0;
            display: grid;
            grid-template-columns: minmax(0, 1fr);
          }

          textarea {
            width: 100%;
            height: 100%;
            padding: 1rem 1.1rem;
            border: 0;
            background: var(--bg);
            color: var(--text);
            font-family: var(--font-mono);
            font-size: 0.9rem;
            line-height: 1.5;
            resize: none;
          }

          :scope[data-wrap="false"] textarea {
            white-space: pre;
            overflow-wrap: normal;
            overflow-x: auto;
          }

          textarea:focus-visible {
            outline: none;
          }

          .preview {
            display: none;
            overflow: auto;
            padding: 1rem 1.1rem;
            border-left: 1px solid var(--border);
            background: var(--surface);
            line-height: 1.5;
          }

          :scope[data-wrap="true"] .preview pre {
            white-space: pre-wrap;
          }

          .preview .empty {
            margin: 0;
          }

          @media (min-width: 48rem) {
            :scope[data-preview="true"] form {
              grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
            }

            :scope[data-preview="true"] .preview {
              display: block;
            }
          }

          @media (max-width: 47.99rem) {
            .toggle.preview-toggle {
              display: none;
            }
          }
        }
      </style>
      <header>
        <h2 id={"inspector-#{@form}-notes-dialog-title"}>Notes · {@record.title}</h2>
        <button
          type="button"
          id={"inspector-#{@form}-notes-preview-toggle"}
          class="toggle preview-toggle"
          data-toggle="preview"
          aria-pressed="true"
          phx-mounted={JS.ignore_attributes(["aria-pressed"])}
        >
          <Lucideicons.columns_2 class="icon" /> Preview
        </button>
        <button
          type="button"
          id={"inspector-#{@form}-notes-wrap-toggle"}
          class="toggle"
          data-toggle="wrap"
          aria-pressed="true"
          phx-mounted={JS.ignore_attributes(["aria-pressed"])}
        >
          <Lucideicons.wrap_text class="icon" /> Wrap
        </button>
        <button
          type="button"
          class="close"
          commandfor={"inspector-#{@form}-notes-dialog"}
          command="close"
          aria-label="Close"
          title="Close"
        >
          <Lucideicons.minimize_2 class="icon" />
        </button>
      </header>
      <form
        id={"inspector-#{@form}-notes-dialog-form"}
        phx-change="save"
        data-autosave
        phx-submit="save"
        phx-target={@myself}
      >
        <textarea
          id={"inspector-#{@form}-notes-wide"}
          name={"#{@form}[notes]"}
          aria-label="Notes"
          placeholder="Markdown is fine…"
          spellcheck="false"
          phx-debounce="300"
        >{@record.notes}</textarea>
        <div class="preview" id={"inspector-#{@form}-notes-preview"} aria-label="Preview">
          <MarskalWeb.FormattedNotes.block text={@record.notes} />
          <p :if={@record.notes in [nil, ""]} class="empty">The formatted notes show here.</p>
        </div>
      </form>
    </dialog>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".NotesDialog" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      const outside = (el: Element, event: MouseEvent) => {
        const box = el.getBoundingClientRect()
        return event.clientX < box.left || event.clientX > box.right ||
          event.clientY < box.top || event.clientY > box.bottom
      }

      const settings = ["preview", "wrap"] as const
      type Setting = (typeof settings)[number]
      const storageKey = (setting: Setting) => `marskal:notes-dialog:${setting}`

      const stored = (setting: Setting): string | null => {
        try {
          return localStorage.getItem(storageKey(setting))
        } catch {
          return null
        }
      }

      // The expand and close buttons open and close the dialog themselves
      // (commandfor). Opening takes the inspector's text and caret, which may
      // be ahead of the server; closing hands the text back, and the
      // inspector's form posts it if a pending save in here has not. A click
      // on the backdrop closes it too.
      export default class extends ViewHook<HTMLDialogElement> {
        mounted() {
          for (const setting of settings) this.apply(setting, stored(setting) !== "false")
          this.el.addEventListener("toggle", (event) => {
            const inline = document.getElementById(this.el.dataset.inline ?? "")
            const wide = this.el.querySelector("textarea")
            if (!(inline instanceof HTMLTextAreaElement) || !wide) return
            if ((event as ToggleEvent).newState === "open") {
              wide.value = inline.value
              wide.focus()
              wide.setSelectionRange(inline.selectionStart, inline.selectionEnd)
            } else if (inline.value !== wide.value) {
              inline.value = wide.value
              inline.dispatchEvent(new Event("input", {bubbles: true}))
            }
          })
          this.el.addEventListener("click", (event) => {
            if (!(event.target instanceof Element)) return
            const toggle = event.target.closest<HTMLElement>("[data-toggle]")
            if (toggle) {
              const setting = toggle.dataset.toggle as Setting
              const on = this.el.dataset[setting] !== "true"
              this.apply(setting, on)
              try {
                localStorage.setItem(storageKey(setting), String(on))
              } catch {}
            } else if (event.target === this.el && outside(this.el, event)) {
              this.el.close()
            }
          })
        }

        apply(setting: Setting, on: boolean) {
          this.el.dataset[setting] = String(on)
          this.el.querySelector(`[data-toggle="${setting}"]`)?.setAttribute("aria-pressed", String(on))
        }
      }
    </script>
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
  # Typing in a date field reads the text and shows what it means; it
  # saves on date-commit (ADR 0032).
  def handle_event("save", %{"_target" => [form, target]} = params, socket)
      when is_map_key(@date_texts, target) and form in ["task", "project"] do
    %{user: user, record: record} = socket.assigns
    key = Map.fetch!(@date_texts, target)
    preview = MarskalWeb.DateFields.preview(key, params[form][target] || "", record, user)
    {:noreply, update(socket, :date_previews, &Map.put(&1, key, preview))}
  end

  def handle_event("save", %{"task" => params}, socket) do
    attrs =
      params
      |> Map.take(["title", "notes", "url", "flagged", "state"])
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

  def handle_event("date-commit", %{"key" => key, "text" => text}, socket)
      when key in ["defer", "planned", "due"] do
    %{user: user, record: record} = socket.assigns

    case MarskalWeb.DateFields.commit(key, text, record, user) do
      {:ok, attrs} ->
        {:noreply, socket} = save(socket, &update_dates(record, &1, &2, attrs, &3))
        socket = update(socket, :date_previews, &Map.delete(&1, key))
        field = MarskalWeb.DateFields.field(key)
        zone = Marskal.Accounts.timezone(user)
        text = MarskalWeb.DateFields.text(Map.fetch!(socket.assigns.record, field), field, zone)
        {:reply, %{text: text}, socket}

      :error ->
        {:reply, %{}, update(socket, :date_previews, &Map.put(&1, key, {:error, text}))}
    end
  end

  def handle_event("calendar-open", %{"key" => key}, socket)
      when key in ["defer", "planned", "due"] do
    %{user: user, record: record} = socket.assigns
    {:noreply, assign(socket, :calendar, MarskalWeb.DateFields.open_calendar(key, record, user))}
  end

  def handle_event("calendar-month", %{"step" => step}, socket) when step in ["-1", "1"] do
    calendar =
      socket.assigns.calendar &&
        MarskalWeb.DateFields.step_calendar(socket.assigns.calendar, String.to_integer(step))

    {:noreply, assign(socket, :calendar, calendar)}
  end

  def handle_event("calendar-close", _params, socket),
    do: {:noreply, assign(socket, :calendar, nil)}

  def handle_event("calendar-pick", %{"key" => key, "date" => iso}, socket)
      when key in ["defer", "planned", "due"] do
    %{user: user, record: record} = socket.assigns

    case Date.from_iso8601(iso) do
      {:ok, date} ->
        attrs = MarskalWeb.DateFields.pick(key, date, record, user)
        {:noreply, socket} = save(socket, &update_dates(record, &1, &2, attrs, &3))

        {:noreply,
         socket
         |> assign(:calendar, nil)
         |> update(:date_previews, &Map.delete(&1, key))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", _params, socket) do
    %{user: user, record: record} = socket.assigns

    result =
      case record do
        %Tasks.Task{} ->
          Tasks.delete_task(user, record.id, Ecto.UUID.generate(version: 7))

        %Projects.Project{} ->
          Projects.delete_project(user, record.id, Ecto.UUID.generate(version: 7))
      end

    case result do
      {:ok, _} -> {:noreply, assign(socket, record: nil, error: nil)}
      {:error, _} -> {:noreply, assign(socket, :error, "Could not delete.")}
    end
  end

  def handle_event("tag-delete", _params, socket) do
    %{user: user, record: record} = socket.assigns

    case Tags.delete_tag(user, record.id, Ecto.UUID.generate(version: 7)) do
      {:ok, _} -> {:noreply, assign(socket, record: nil, error: nil)}
      {:error, _} -> {:noreply, assign(socket, :error, "Could not delete the tag.")}
    end
  end

  def handle_event("tag-search", %{"tag_query" => query}, socket) do
    {:noreply,
     assign(socket, :picker, %{
       query: query,
       parent: socket.assigns.picker[:parent] || "",
       results: suggestions(socket, query)
     })}
  end

  def handle_event("tag-parent", %{"tag_parent" => parent}, socket) do
    {:noreply, update(socket, :picker, &Map.put(&1, :parent, parent))}
  end

  def handle_event("location-open", _params, socket) do
    targets = locations(socket.assigns)
    {:noreply, assign(socket, :place, %{targets: targets, query: "", results: browse(targets)})}
  end

  def handle_event("location-search", %{"location_query" => query}, socket) do
    targets =
      case socket.assigns.place do
        %{targets: targets} -> targets
        nil -> locations(socket.assigns)
      end

    results = if String.trim(query) == "", do: browse(targets), else: GoTo.run(targets, query)
    {:noreply, assign(socket, :place, %{targets: targets, query: query, results: results})}
  end

  def handle_event("location-close", _params, socket), do: {:noreply, assign(socket, :place, nil)}

  def handle_event("location-pick", %{"location" => value}, socket) do
    attrs = value |> MarskalWeb.TaskComponents.parse_location() |> Tasks.location_attrs()
    socket |> assign(:place, nil) |> save(&Tasks.update_task(&1, &2, attrs, &3))
  end

  def handle_event("tag-add", %{"id" => tag_id}, socket), do: link_tag(socket, :tag, tag_id)
  def handle_event("tag-remove", %{"id" => tag_id}, socket), do: link_tag(socket, :untag, tag_id)

  def handle_event("tag-pick", params, socket) do
    %{query: stored_query, results: results} = socket.assigns.picker
    query = params["tag_query"] || stored_query

    parent =
      case params do
        %{"tag_parent" => parent} -> parent
        _ -> socket.assigns.picker[:parent] || ""
      end

    case {params["action"], results} do
      {"create", _} -> create_and_link(socket, query, parent)
      {_, [first | _]} -> link_tag(socket, :tag, first.id)
      {_, []} -> create_and_link(socket, query, parent)
    end
  end

  defp empty_picker, do: %{query: "", results: [], parent: ""}

  # Each save is one command carrying only the fields that differ. The form
  # posts its whole state, so a resent event changes nothing and needs no
  # client-side command id.
  defp save(socket, update) do
    %{user: user, record: record} = socket.assigns

    case update.(user, record.id, Ecto.UUID.generate(version: 7)) do
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

  defp update_dates(%Tasks.Task{}, user, id, attrs, command),
    do: Tasks.update_task(user, id, attrs, command)

  defp update_dates(%Projects.Project{}, user, id, attrs, command),
    do: Projects.update_project(user, id, attrs, command)

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
          Tags.tag_task(user, record.id, tag_id, Ecto.UUID.generate(version: 7))

        {%Tasks.Task{}, :untag} ->
          Tags.untag_task(user, record.id, tag_id, Ecto.UUID.generate(version: 7))

        {%Projects.Project{}, :tag} ->
          Tags.tag_project(user, record.id, tag_id, Ecto.UUID.generate(version: 7))

        {%Projects.Project{}, :untag} ->
          Tags.untag_project(user, record.id, tag_id, Ecto.UUID.generate(version: 7))
      end

    case result do
      {:ok, _link} ->
        {:noreply,
         assign(socket,
           tagging: tagging(user, record),
           picker: empty_picker(),
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

    case Tags.create_tag(socket.assigns.user, attrs, Ecto.UUID.generate(version: 7)) do
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
    do: datetime |> DateTime.shift_zone!(zone) |> Marskal.DateFormat.date_time()

  defp stamp(_datetime, _zone), do: ""

  # Deleting the open occurrence of a series ends the series (ADR 0007).
  defp delete_task_confirm(%Tasks.Task{series_id: id, state: :to_do}) when is_binary(id),
    do: "Delete this task and end its repeat? To skip only this one, use Dropped."

  defp delete_task_confirm(_task),
    do: "Delete this task? To finish it or give it up, use Done or Dropped."

  defp delete_project_confirm(%Projects.Project{series_id: id, state: :to_do})
       when is_binary(id),
       do:
         "Delete this project and every task in it, and end its repeat? To skip only this one, use Dropped."

  defp delete_project_confirm(_project),
    do:
      "Delete this project and every task in it? To finish it or give it up, use Done or Dropped."

  # Where a task can move: the inbox, no project, and every open project,
  # with its own even if resolved. A project the sidebar hides, deferred or
  # in a dropped folder, is dimmed and ranks after those it shows.
  defp locations(%{user: user, record: %Tasks.Task{} = task}) do
    projects =
      user
      |> GoTo.projects()
      |> Enum.filter(&(&1.state == :to_do or &1.id == task.project_id))

    [
      %GoTo.Target{type: :view, id: :inbox, path: [gettext("Inbox")]},
      %GoTo.Target{type: :view, id: :none, path: [gettext("No project")]}
      | projects
    ]
  end

  # A blank query lists every location, in sidebar order, hidden ones last.
  defp browse(targets), do: Enum.sort_by(targets, & &1.hidden)

  defp location_text(task, projects) do
    case Tasks.location(task) do
      :inbox -> gettext("Inbox")
      :none -> gettext("No project")
      id -> Enum.find_value(projects, "", &(&1.id == id && &1.title))
    end
  end

  # A location as `MarskalWeb.TaskComponents.parse_location/1` reads it.
  defp location_value(%GoTo.Target{type: :view, id: id}), do: Atom.to_string(id)
  defp location_value(%GoTo.Target{id: id}), do: id

  defp location_value(%Tasks.Task{} = task) do
    case Tasks.location(task) do
      id when is_atom(id) -> Atom.to_string(id)
      id -> id
    end
  end

  # The date inputs are only on the task and project forms. A post from
  # elsewhere, without them, leaves the dates alone.
  defp date_params(%{"due_date" => _} = params, socket) do
    %{user: user, record: record} = socket.assigns
    MarskalWeb.DateFields.params_to_attrs(params, record, Marskal.Accounts.timezone(user))
  end

  defp date_params(_params, _socket), do: %{}
end
