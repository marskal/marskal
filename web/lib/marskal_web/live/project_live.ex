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
         socket
         |> put_flash(:error, "That project is not available.")
         |> MarskalWeb.UserAuth.redirect_home()}

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
      visibility={assigns[:visibility]}
    >
      <p :if={@folder} class="lede">
        <.link
          navigate={MarskalWeb.NavComponents.record_path(:folder, @folder.id)}
          data-opens-inspector
        >{@folder.name}</.link>
      </p>
      <MarskalWeb.NavComponents.page_heading type={:project} id={@project.id} inspector={@inspector}>
        {@project.title}
        <:extra>
          <.project_summary counts={@task_counts} />
        </:extra>
      </MarskalWeb.NavComponents.page_heading>
      <p :if={@project.url} class="lede"><MarskalWeb.UrlLink.link url={@project.url} text /></p>
      <MarskalWeb.FormattedNotes.block text={@project.notes} class="lede notes" />
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
        new_row={@new_row}
        zone={Marskal.Accounts.timezone(@current_scope.user)}
        actions={[:complete]}
        inspector={@inspector}
      />

      <%!-- Below the list, as a new task goes last in the project. --%>
      <.add_form
        id="new-project-task"
        for={@form}
        field={@form[:title]}
        label={gettext("Add a task")}
        command_id={@command_id}
        phx-submit="create"
        data-new-task="task"
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
      <p
        :if={!@open? and @project.state == :to_do and @task_counts.to_do > 0}
        id="project-hidden"
        class="empty"
      >
        {gettext("Its tasks still to do are deferred. Show deferred to see them.")}
      </p>
      <.empty_state
        :if={!@open? and @project.state == :to_do and @has_tasks? and @task_counts.to_do == 0}
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
    show = socket.assigns.visibility
    open_tasks = Tasks.list_project_tasks(user, project.id, show: show)

    folder =
      if project.project_folder_id do
        Marskal.ProjectFolders.get_folder(user, project.project_folder_id)
      end

    counts = Tasks.project_task_counts(user, project.id)

    socket
    |> assign(:page_title, project.title)
    |> assign(:project, project)
    |> assign(:folder, folder)
    |> assign(:open?, open_tasks != [])
    |> assign(:task_counts, counts)
    |> assign(:has_tasks?, counts.total > 0)
    |> assign_tasks(open_tasks)
  end

  attr :counts, :map, required: true

  defp project_summary(assigns) do
    assigns = assign(assigns, :parts, shown_counts(assigns.counts))

    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.project-summary) {
        :scope {
          display: flex;
          flex: 0 0 auto;
          align-items: baseline;
          max-width: 100%;
          min-width: 0;
          color: var(--muted);
          font-size: 1rem;
          font-weight: 400;
          line-height: 1.5;
          font-variant-numeric: tabular-nums;
        }

        .line,
        .counts,
        .part,
        .count {
          display: inline-flex;
          align-items: center;
          max-width: 100%;
        }

        .line {
          flex-wrap: wrap;
          gap: 0.35rem 0.5rem;
        }

        .counts,
        .part {
          gap: 0.15rem;
        }

        .count {
          gap: 0.2rem;
        }

        .count .icon {
          width: 1rem;
          height: 1rem;
        }

        .count--open {
          color: var(--text);
        }

        .count--dropped {
          color: var(--muted);
        }

        .count--done {
          color: var(--accent);
        }
      }
    </style>
    <span id="project-summary" class="project-summary">
      <span class="sr-only">{summary_label(@counts)}</span>
      <span class="line" aria-hidden="true">
        <span class="total">{total_label(@counts)}</span>
        <span :if={@parts != []} class="counts">
          <span class="paren">(</span>
          <span :for={{part, index} <- Enum.with_index(@parts)} class="part">
            <span :if={index > 0} class="sep">/</span>
            <span class={["count", "count--#{part.state}"]} title={part.label}>
              <Lucideicons.square :if={part.state == :open} class="icon" />
              <Lucideicons.square_off :if={part.state == :dropped} class="icon" />
              <Lucideicons.square_check_big :if={part.state == :done} class="icon" />
              <span class="n">{part.n}</span>
            </span>
          </span>
          <span class="paren">)</span>
        </span>
      </span>
    </span>
    """
  end

  defp shown_counts(counts) do
    for {state, n, label} <- [
          {:open, counts.to_do, gettext("Open")},
          {:dropped, counts.dropped, gettext("Dropped")},
          {:done, counts.done, gettext("Done")}
        ],
        n > 0,
        do: %{state: state, n: n, label: label}
  end

  defp total_label(%{total: total}) do
    ngettext("1 task", "%{count} tasks", total, count: total)
  end

  defp summary_label(%{to_do: open, dropped: dropped, done: done} = counts)
       when open > 0 and dropped > 0 and done > 0 do
    ngettext(
      "1 task: %{open} open, %{dropped} dropped, and %{done} done",
      "%{count} tasks: %{open} open, %{dropped} dropped, and %{done} done",
      counts.total,
      count: counts.total,
      open: open,
      dropped: dropped,
      done: done
    )
  end

  defp summary_label(%{to_do: open, dropped: dropped, done: 0} = counts)
       when open > 0 and dropped > 0 do
    ngettext(
      "1 task: %{open} open and %{dropped} dropped",
      "%{count} tasks: %{open} open and %{dropped} dropped",
      counts.total,
      count: counts.total,
      open: open,
      dropped: dropped
    )
  end

  defp summary_label(%{to_do: open, dropped: 0, done: done} = counts)
       when open > 0 and done > 0 do
    ngettext(
      "1 task: %{open} open and %{done} done",
      "%{count} tasks: %{open} open and %{done} done",
      counts.total,
      count: counts.total,
      open: open,
      done: done
    )
  end

  defp summary_label(%{to_do: 0, dropped: dropped, done: done} = counts)
       when dropped > 0 and done > 0 do
    ngettext(
      "1 task: %{dropped} dropped and %{done} done",
      "%{count} tasks: %{dropped} dropped and %{done} done",
      counts.total,
      count: counts.total,
      dropped: dropped,
      done: done
    )
  end

  defp summary_label(%{to_do: open, dropped: 0, done: 0} = counts) when open > 0 do
    ngettext("1 task: %{open} open", "%{count} tasks: %{open} open", counts.total,
      count: counts.total,
      open: open
    )
  end

  defp summary_label(%{to_do: 0, dropped: dropped, done: 0} = counts) when dropped > 0 do
    ngettext(
      "1 task: %{dropped} dropped",
      "%{count} tasks: %{dropped} dropped",
      counts.total,
      count: counts.total,
      dropped: dropped
    )
  end

  defp summary_label(%{to_do: 0, dropped: 0, done: done} = counts) when done > 0 do
    ngettext("1 task: %{done} done", "%{count} tasks: %{done} done", counts.total,
      count: counts.total,
      done: done
    )
  end

  defp summary_label(counts), do: total_label(counts)
end
