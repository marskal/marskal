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

  alias Marskal.Tags
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
    |> attach_hook(:outline_info, :handle_info, &handle_info/2)
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
  # subtask, as it reads on screen. The inspector edits that draft — URL,
  # notes, and the rest — and Enter saves them with the task.
  defp handle_event("inline-new", %{"id" => id, "where" => where}, socket)
       when where in ["above", "below"] do
    user = socket.assigns.current_scope.user

    case Tasks.get_task(user, id) do
      nil ->
        {:halt, socket}

      anchor ->
        where = String.to_existing_atom(where)
        {:halt, assign(socket, :new_row, new_row(user, anchor, where, socket.assigns.collapsed))}
    end
  end

  # Enter adds the task and opens the next row below it, for a list typed
  # in one go. An empty row ends. The title here is what the row holds;
  # the inspector's fields are already on the draft.
  defp handle_event("inline-create", %{"title" => title}, socket) do
    case {socket.assigns.new_row, String.trim(title)} do
      {nil, _title} -> {:halt, socket}
      {draft, ""} -> {:halt, close(socket, draft.anchor_id)}
      {draft, title} -> {:halt, create(socket, %{draft | title: title}, title)}
    end
  end

  # The outline title, as it is typed, so the inspector shows the same one.
  defp handle_event("inline-title", %{"title" => title}, socket) do
    case socket.assigns.new_row do
      nil -> {:halt, socket}
      draft -> {:halt, assign(socket, :new_row, %{draft | title: title, error: nil})}
    end
  end

  defp handle_event("inline-cancel", _params, socket) do
    case socket.assigns.new_row do
      nil -> {:halt, socket}
      draft -> {:halt, close(socket, draft.anchor_id)}
    end
  end

  # Leaving the row closes it when nothing was typed. A typed title waits.
  # Moving into the inspector is not leaving: the hook does not send this.
  defp handle_event("inline-blur", params, socket) do
    case {socket.assigns.new_row, String.trim(params["value"] || "")} do
      {%{}, ""} -> {:halt, assign(socket, :new_row, nil)}
      _ -> {:halt, socket}
    end
  end

  # The new-task form posts here, not to the inspector component, so the
  # draft changes in this same event. A message would be applied after the
  # reply, and the form would paint the draft from before the keystroke.
  defp handle_event("draft-save", %{"_target" => ["task", target]} = params, socket)
       when target in ["defer_text", "planned_text", "due_text"] do
    case socket.assigns.new_row do
      nil ->
        {:halt, socket}

      draft ->
        key = %{"defer_text" => "defer", "planned_text" => "planned", "due_text" => "due"}

        preview =
          MarskalWeb.DateFields.preview(
            key[target],
            params["task"][target] || "",
            draft_record(draft),
            socket.assigns.current_scope.user
          )

        previews = Map.put(draft.date_previews, key[target], preview)
        {:halt, assign(socket, :new_row, %{draft | date_previews: previews})}
    end
  end

  defp handle_event("draft-save", %{"task" => params}, socket) do
    case socket.assigns.new_row do
      nil ->
        {:halt, socket}

      draft ->
        patch = fields(params)
        draft = Map.merge(draft, patch)

        {:halt, socket |> assign(:new_row, draft) |> push_draft_title(patch, draft)}
    end
  end

  # Enter in the inspector. An empty title waits; the outline's own Enter
  # is what ends an empty row.
  defp handle_event("draft-create", %{"task" => params}, socket) do
    case socket.assigns.new_row do
      nil ->
        {:halt, socket}

      draft ->
        draft = Map.merge(draft, fields(params))
        title = String.trim(draft.title || "")

        if title == "" do
          {:halt, assign(socket, :new_row, draft)}
        else
          {:halt, create(socket, draft, title)}
        end
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  # The inspector edits the draft and sends the change here. Patches merge
  # onto the current draft, so an older round trip cannot drop a newer one.
  defp handle_info({:new_task_patch, patch}, socket) when is_map(patch) do
    case socket.assigns[:new_row] do
      nil ->
        {:halt, socket}

      draft ->
        draft = Map.merge(draft, patch)
        {:halt, socket |> assign(:new_row, draft) |> push_draft_title(patch, draft)}
    end
  end

  defp handle_info({:new_task_location, %{inbox: inbox, project_id: project_id}}, socket) do
    case socket.assigns[:new_row] do
      nil ->
        {:halt, socket}

      draft ->
        home? = inbox == draft.home_inbox and project_id == draft.home_project_id

        draft = %{
          draft
          | inbox: inbox,
            project_id: project_id,
            parent_id: if(home?, do: draft.home_parent_id, else: nil),
            error: nil
        }

        {:halt, assign(socket, :new_row, draft)}
    end
  end

  defp handle_info({:new_task_tag, action, tag_id}, socket) when action in [:add, :remove] do
    case socket.assigns[:new_row] do
      nil ->
        {:halt, socket}

      draft ->
        tag_ids =
          case action do
            :add -> Enum.uniq(draft.tag_ids ++ [tag_id])
            :remove -> Enum.reject(draft.tag_ids, &(&1 == tag_id))
          end

        {:halt, assign(socket, :new_row, %{draft | tag_ids: tag_ids, error: nil})}
    end
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp new_row(user, anchor, where, collapsed) do
    {child?, parent_id} =
      case where do
        :below ->
          child? =
            not MapSet.member?(collapsed, anchor.id) and
              Marskal.Tasks.Outline.children(anchor) != []

          {child?, if(child?, do: anchor.id, else: anchor.parent_id)}

        :above ->
          {false, anchor.parent_id}
      end

    parent_title =
      cond do
        is_nil(parent_id) -> nil
        parent_id == anchor.id -> anchor.title
        true -> user |> Tasks.get_task(parent_id) |> then(&(&1 && &1.title))
      end

    %{
      anchor_id: anchor.id,
      where: where,
      child?: child?,
      home_inbox: anchor.inbox,
      home_project_id: anchor.project_id,
      home_parent_id: parent_id,
      parent_title: parent_title,
      title: "",
      notes: "",
      url: "",
      flagged: false,
      state: :to_do,
      inbox: anchor.inbox,
      project_id: anchor.project_id,
      parent_id: parent_id,
      defer_until: nil,
      deferred_indefinitely: false,
      planned_at: nil,
      due_at: nil,
      tag_ids: [],
      date_previews: %{},
      error: nil
    }
  end

  defp create(socket, draft, title) do
    user = socket.assigns.current_scope.user

    case Tasks.get_task(user, draft.anchor_id) do
      nil ->
        socket
        |> assign(:new_row, nil)
        |> put_flash(:error, gettext("Could not add the task."))

      anchor ->
        insert(socket, user, anchor, draft, title)
    end
  end

  defp insert(socket, user, anchor, draft, title) do
    case Tasks.create_task(
           user,
           new_attrs(anchor, draft, title),
           Ecto.UUID.generate(version: 7)
         ) do
      {:ok, task} ->
        socket
        |> note_tag_failure(user, task, draft.tag_ids)
        |> follow_on(user, draft, task)

      {:error, %Ecto.Changeset{} = changeset} ->
        draft = %{draft | title: title, error: changeset_error(changeset)}

        socket
        |> assign(:new_row, draft)
        |> push_event("inline-title", %{title: title})

      {:error, _} ->
        socket
        |> assign(:new_row, %{draft | title: title})
        |> put_flash(:error, gettext("Could not add the task."))
    end
  end

  defp note_tag_failure(socket, user, task, tag_ids) do
    case tag_draft(user, task, tag_ids) do
      :ok ->
        socket

      {:error, _} ->
        put_flash(socket, :error, gettext("The task was added, but a tag could not."))
    end
  end

  # A task filed somewhere else is not in this outline, so the next row
  # would have nothing to sit under.
  defp follow_on(socket, user, draft, task) do
    if moved?(draft),
      do: close(socket, draft.anchor_id),
      else: assign(socket, :new_row, new_row(user, task, :below, MapSet.new()))
  end

  defp push_draft_title(socket, patch, draft) do
    if Map.has_key?(patch, :title),
      do: push_event(socket, "inline-title", %{title: draft.title}),
      else: socket
  end

  defp moved?(draft),
    do: draft.inbox != draft.home_inbox or draft.project_id != draft.home_project_id

  defp new_attrs(anchor, draft, title) do
    base = %{
      "title" => title,
      "notes" => blank(draft.notes),
      "url" => blank(draft.url),
      "flagged" => draft.flagged,
      "state" => Atom.to_string(draft.state),
      "inbox" => draft.inbox,
      "project_id" => draft.project_id,
      "defer_until" => draft.defer_until,
      "deferred_indefinitely" => draft.deferred_indefinitely,
      "planned_at" => draft.planned_at,
      "due_at" => draft.due_at
    }

    if moved?(draft) do
      base
    else
      case draft do
        %{child?: true} ->
          first = anchor |> Marskal.Tasks.Outline.children() |> List.first()
          Map.merge(base, %{"parent_id" => anchor.id, "before_id" => first && first.id})

        %{where: :below} ->
          Map.merge(base, %{"parent_id" => anchor.parent_id, "after_id" => anchor.id})

        %{where: :above} ->
          Map.merge(base, %{"parent_id" => anchor.parent_id, "before_id" => anchor.id})
      end
    end
  end

  defp fields(params) do
    params
    |> Map.take(["title", "notes", "url", "flagged", "state", "deferred_indefinitely"])
    |> Enum.reduce(%{}, fn
      {"title", title}, patch ->
        Map.put(patch, :title, title)

      {"notes", notes}, patch ->
        Map.put(patch, :notes, notes || "")

      {"url", url}, patch ->
        Map.put(patch, :url, url || "")

      {"flagged", flagged}, patch ->
        Map.put(patch, :flagged, flagged in [true, "true"])

      {"state", state}, patch ->
        Map.put(patch, :state, state_atom(state))

      {"deferred_indefinitely", value}, patch ->
        Map.put(patch, :deferred_indefinitely, value in [true, "true"])
    end)
    |> Map.put(:error, nil)
  end

  defp state_atom(value) when value in ~w(to_do done dropped), do: String.to_existing_atom(value)
  defp state_atom(_value), do: :to_do

  # What the date fields read. They need the draft's current values.
  defp draft_record(draft) do
    %Tasks.Task{
      title: draft.title,
      notes: draft.notes,
      url: draft.url,
      flagged: draft.flagged,
      state: draft.state,
      inbox: draft.inbox,
      project_id: draft.project_id,
      parent_id: draft.parent_id,
      defer_until: draft.defer_until,
      deferred_indefinitely: draft.deferred_indefinitely,
      planned_at: draft.planned_at,
      due_at: draft.due_at
    }
  end

  defp blank(nil), do: nil

  defp blank(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp tag_draft(_user, _task, []), do: :ok

  defp tag_draft(user, task, tag_ids) do
    Enum.reduce_while(tag_ids, :ok, fn tag_id, :ok ->
      case Tags.tag_task(user, task.id, tag_id, Ecto.UUID.generate(version: 7)) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp changeset_error(changeset) do
    {field, error} = hd(changeset.errors)
    "#{field_label(field)} #{MarskalWeb.CoreComponents.translate_error(error)}."
  end

  defp field_label(:url), do: "URL"
  defp field_label(field), do: Phoenix.Naming.humanize(field)

  # Focus goes back to the row the new one was opened from, or the last
  # task added.
  defp close(socket, anchor_id) do
    socket
    |> assign(:new_row, nil)
    |> push_event("outline-focus", %{id: anchor_id})
  end
end
