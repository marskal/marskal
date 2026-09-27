defmodule MarskalWeb.TaskLive do
  use MarskalWeb, :live_view

  alias Marskal.Projects
  alias Marskal.Tasks

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Tasks.get_task(user, id) do
      nil ->
        {:ok, socket |> put_flash(:error, "That task is not available.") |> redirect(to: ~p"/")}

      task ->
        {:ok, assign_task(socket, user, task)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <h1>Task</h1>
      <.form for={@form} id="task-form" phx-submit="save" class="capture">
        <label for={@form[:title].id}>Title</label>
        <input
          type="text"
          name={@form[:title].name}
          id={@form[:title].id}
          value={@form[:title].value}
          required
        />
        <p :for={error <- @form[:title].errors} class="field-error">{translate_error(error)}</p>
        <label for={@form[:notes].id}>Notes</label>
        <textarea
          name={@form[:notes].name}
          id={@form[:notes].id}
          rows="4"
          placeholder="Markdown is fine…"
        >{@form[:notes].value}</textarea>
        <label for="task-location">Location</label>
        <MarskalWeb.TaskComponents.location_select
          id="task-location"
          name="task[location]"
          task={@task}
          projects={@projects}
        />
        <button type="submit">Save</button>
      </.form>
      <p class="actions">
        <button :if={@task.state == :to_do} type="button" phx-click="complete">Done</button>
        <button :if={@task.state == :to_do} type="button" phx-click="drop">Drop</button>
        <button :if={@task.state != :to_do} type="button" phx-click="reopen">Reopen</button>
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:marskal_change, type, id}, socket) do
    user = socket.assigns.current_scope.user
    task = socket.assigns.task

    socket =
      if type in ["task", "import_batch"] and (type != "task" or id == task.id) do
        case Tasks.get_task(user, task.id) do
          nil -> socket
          task -> assign_task(socket, user, task)
        end
      else
        assign(socket, :projects, Projects.list_open(user))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"task" => params}, socket) do
    user = socket.assigns.current_scope.user
    location = MarskalWeb.TaskComponents.parse_location(params["location"] || "none")

    attrs =
      params
      |> Map.take(["title", "notes"])
      |> Map.merge(Map.new(Tasks.location_attrs(location), fn {k, v} -> {to_string(k), v} end))

    case Tasks.update_task(user, socket.assigns.task.id, attrs, Ecto.UUID.generate()) do
      {:ok, task} ->
        {:noreply, assign_task(socket, user, task) |> put_flash(:info, "Saved.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "task", action: :validate))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save task.")}
    end
  end

  def handle_event("complete", _params, socket), do: act(socket, &Tasks.complete_task/3)
  def handle_event("drop", _params, socket), do: act(socket, &Tasks.drop_task/3)
  def handle_event("reopen", _params, socket), do: act(socket, &Tasks.reopen_task/3)

  defp act(socket, fun) do
    user = socket.assigns.current_scope.user

    case fun.(user, socket.assigns.task.id, Ecto.UUID.generate()) do
      {:ok, task} -> {:noreply, assign_task(socket, user, task)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update task.")}
    end
  end

  defp assign_task(socket, user, task) do
    socket
    |> assign(:page_title, task.title)
    |> assign(:task, task)
    |> assign(:projects, Projects.list_open(user))
    |> assign(
      :form,
      to_form(
        %{
          "title" => task.title,
          "notes" => task.notes
        },
        as: "task"
      )
    )
  end
end
