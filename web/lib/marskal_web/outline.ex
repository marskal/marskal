defmodule MarskalWeb.Outline do
  @moduledoc """
  The outline events of a task list shown with `outline: true`: collapse,
  and the keyboard moves from the `.Outline` hook (ADR 0009, ADR 0031).

  `attach/1` adds them to a LiveView, and the task actions those keys
  send (`MarskalWeb.TaskKeys`). A move goes through `Marskal.Tasks`,
  and the change broadcast reloads the list, as any other write does.
  Collapsed ids belong to the browser: the hook sends its saved set on
  mount and saves what the server sends back after each toggle.
  """

  use Gettext, backend: MarskalWeb.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3, put_flash: 3]

  alias Marskal.Tasks

  @moves %{
    "outline-indent" => &Tasks.indent_task/3,
    "outline-outdent" => &Tasks.outdent_task/3,
    "outline-up" => &Tasks.move_task_up/3,
    "outline-down" => &Tasks.move_task_down/3
  }

  @move_events Map.keys(@moves)

  def attach(socket) do
    socket
    |> assign(:collapsed, MapSet.new())
    |> assign(:new_row, nil)
    |> MarskalWeb.TaskKeys.attach()
    |> attach_hook(:outline, :handle_event, &handle_event/3)
  end

  defp handle_event("outline-collapsed", %{"ids" => ids}, socket) when is_list(ids),
    do: {:halt, assign(socket, :collapsed, MapSet.new(ids, &to_string/1))}

  defp handle_event("outline-toggle", %{"id" => id}, socket) do
    collapsed = socket.assigns.collapsed

    collapsed =
      if MapSet.member?(collapsed, id),
        do: MapSet.delete(collapsed, id),
        else: MapSet.put(collapsed, id)

    {:halt,
     socket
     |> assign(:collapsed, collapsed)
     |> push_event("outline-collapsed", %{ids: MapSet.to_list(collapsed)})}
  end

  defp handle_event(event, %{"id" => id}, socket) when event in @move_events do
    user = socket.assigns.current_scope.user

    case @moves[event].(user, id, Ecto.UUID.generate(version: 7)) do
      {:ok, _task} ->
        {:halt, socket}

      # Nothing to indent under, out of, or past: the key does nothing.
      {:error, reason} when reason in [:first, :last, :top_level] ->
        {:halt, socket}

      {:error, _} ->
        {:halt, put_flash(socket, :error, "Could not move that task.")}
    end
  end

  # A drop: under `parent_id`, after `after_id` (either may be nil).
  defp handle_event("outline-place", %{"id" => id} = params, socket) do
    user = socket.assigns.current_scope.user

    case Tasks.place_task(
           user,
           id,
           params["parent_id"],
           params["after_id"],
           Ecto.UUID.generate(version: 7)
         ) do
      {:ok, _task} -> {:halt, socket}
      {:error, _} -> {:halt, put_flash(socket, :error, "Could not move that task there.")}
    end
  end

  # A task added inline (ADR 0031): `o` opens a row below `id`, `O` one
  # above. Below a row whose subtasks show, the new task is its first
  # subtask, as it reads on screen. Leaving the title saves it, and the
  # inspector edits that task. Enter saves it and opens the next row.
  defp handle_event("inline-new", %{"id" => id, "where" => where}, socket)
       when where in ["above", "below"] do
    user = socket.assigns.current_scope.user

    case Tasks.get_task(user, id) do
      nil ->
        {:halt, socket}

      anchor ->
        where = String.to_existing_atom(where)
        {:halt, assign(socket, :new_row, new_row(anchor, where, socket.assigns.collapsed))}
    end
  end

  # Enter adds the task and opens the next row below it, for a list typed
  # in one go. An empty row ends.
  defp handle_event("inline-create", %{"title" => title}, socket) do
    case {socket.assigns.new_row, String.trim(title)} do
      {nil, _title} -> {:halt, socket}
      {new_row, ""} -> {:halt, close(socket, new_row.anchor_id)}
      {new_row, title} -> {:halt, create(socket, new_row, title)}
    end
  end

  # The outline title and the inspector title stay the same string.
  defp handle_event("inline-title", %{"title" => title}, socket) do
    case socket.assigns.new_row do
      nil ->
        {:halt, socket}

      new_row ->
        socket = assign(socket, :new_row, %{new_row | title: title})
        {:halt, push_event(socket, "inline-title", %{title: title})}
    end
  end

  defp handle_event("inline-cancel", _params, socket) do
    case socket.assigns.new_row do
      nil -> {:halt, socket}
      new_row -> {:halt, close(socket, new_row.anchor_id)}
    end
  end

  # Leaving a title that has text saves the task, and the inspector edits
  # it. An empty title saves nothing. Enter is the outline's own submit,
  # so the hook does not send this then.
  defp handle_event("inline-blur", %{"value" => value}, socket) do
    case {socket.assigns.new_row, String.trim(value || "")} do
      {nil, _title} -> {:halt, socket}
      {_new_row, ""} -> {:halt, assign(socket, :new_row, nil)}
      {new_row, title} -> {:halt, commit(socket, new_row, title)}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp new_row(anchor, :below, collapsed) do
    child? =
      not MapSet.member?(collapsed, anchor.id) and Marskal.Tasks.Outline.children(anchor) != []

    %{anchor_id: anchor.id, where: :below, child?: child?, title: ""}
  end

  defp new_row(anchor, :above, _collapsed),
    do: %{anchor_id: anchor.id, where: :above, child?: false, title: ""}

  # Enter: the task is saved and the next empty row opens under it.
  defp create(socket, new_row, title) do
    case insert(socket, new_row, title) do
      {:ok, socket, task} ->
        assign(socket, :new_row, %{anchor_id: task.id, where: :below, child?: false, title: ""})

      {:error, socket} ->
        socket
    end
  end

  # Leaving the title: the task is saved and the inspector edits it.
  defp commit(socket, new_row, title) do
    case insert(socket, new_row, title) do
      {:ok, socket, task} ->
        socket
        |> assign(:new_row, nil)
        |> MarskalWeb.Inspector.select("task", task.id)
        |> push_event("inspector-focus", %{})

      {:error, socket} ->
        socket
    end
  end

  defp insert(socket, new_row, title) do
    user = socket.assigns.current_scope.user

    with %{} = anchor <- Tasks.get_task(user, new_row.anchor_id),
         {:ok, task} <-
           Tasks.create_task(
             user,
             new_attrs(anchor, new_row, title),
             Ecto.UUID.generate(version: 7)
           ) do
      {:ok, socket, task}
    else
      _ ->
        {:error,
         socket |> assign(:new_row, nil) |> put_flash(:error, gettext("Could not add the task."))}
    end
  end

  defp new_attrs(anchor, new_row, title) do
    base = %{"title" => title, "inbox" => anchor.inbox, "project_id" => anchor.project_id}

    case new_row do
      %{child?: true} ->
        first = anchor |> Marskal.Tasks.Outline.children() |> List.first()
        Map.merge(base, %{"parent_id" => anchor.id, "before_id" => first && first.id})

      %{where: :below} ->
        Map.merge(base, %{"parent_id" => anchor.parent_id, "after_id" => anchor.id})

      %{where: :above} ->
        Map.merge(base, %{"parent_id" => anchor.parent_id, "before_id" => anchor.id})
    end
  end

  # Focus goes back to the row the new one was opened from, or the last
  # task added.
  defp close(socket, anchor_id) do
    socket
    |> assign(:new_row, nil)
    |> push_event("outline-focus", %{id: anchor_id})
  end
end
