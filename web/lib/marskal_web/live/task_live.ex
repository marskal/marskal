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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1>Task</h1>
      <.form for={@form} id="task-form" phx-submit="save" class="capture">
        <label for={@form[:title].id}>Title</label>
        <input type="text" name={@form[:title].name} id={@form[:title].id} value={@form[:title].value} required />
        <label for={@form[:notes].id}>Notes</label>
        <textarea name={@form[:notes].name} id={@form[:notes].id} rows="4">{@form[:notes].value}</textarea>
        <label for={@form[:project_id].id}>Project</label>
        <select name={@form[:project_id].name} id={@form[:project_id].id}>
          <option value="">None</option>
          <option :for={project <- @projects} value={project.id} selected={project.id == @task.project_id}>
            {project.title}
          </option>
        </select>
        <button type="submit">Save</button>
      </.form>
      <p class="actions">
        <button :if={@task.inbox} type="button" phx-click="clarify">Clarify</button>
        <button :if={@task.state == :to_do} type="button" phx-click="complete">Done</button>
        <button :if={@task.state == :to_do} type="button" phx-click="drop">Drop</button>
        <button :if={@task.state != :to_do} type="button" phx-click="reopen">Reopen</button>
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save", %{"task" => params}, socket) do
    user = socket.assigns.current_scope.user
    task = socket.assigns.task

    with {:ok, task} <- Tasks.rename_task(user, task.id, params["title"], Ecto.UUID.generate()),
         {:ok, task} <- Tasks.set_notes(user, task.id, blank_to_nil(params["notes"]), Ecto.UUID.generate()),
         {:ok, task} <- Tasks.file_task(user, task.id, blank_to_nil(params["project_id"]), Ecto.UUID.generate()) do
      {:noreply, assign_task(socket, user, task) |> put_flash(:info, "Saved.")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not save task.")}
    end
  end

  def handle_event("clarify", _params, socket), do: act(socket, &Tasks.clarify_task/3)
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
          "notes" => task.notes,
          "project_id" => task.project_id
        },
        as: "task"
      )
    )
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
