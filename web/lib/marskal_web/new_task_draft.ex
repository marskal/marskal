defmodule MarskalWeb.NewTaskDraft do
  @moduledoc """
  The add field below a task list, shown in the inspector while a title
  is typed into it (ADR 0031), as the outline's new row is.

  `attach/2` adds the events, with where the page files a new task, which
  the inspector shows: task fields and tag ids. The page's own submit
  event still saves the task, and the page calls `created/3` after. Leaving a title that has text submits the form
  with `leave` set, and the inspector then edits the saved task. Enter
  saves it and the field takes the next.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3]

  def attach(socket, attrs, tag_ids \\ []) do
    socket
    |> assign(:draft, nil)
    |> assign(:draft_place, %{attrs: attrs, tag_ids: tag_ids})
    |> attach_hook(:new_task_draft, :handle_event, &handle_event/3)
  end

  @doc """
  After the page has saved the task its field held. A save made by leaving
  the field opens the task in the inspector, and moves focus to the field
  of the same id when focus went to the inspector (`focus`). The field is cleared here, since a focused field
  keeps what was typed in it.
  """
  def created(socket, task, params) do
    socket =
      case socket.assigns.draft do
        nil -> socket
        draft -> socket |> assign(:draft, nil) |> push_event("draft-clear", %{form: draft.form})
      end

    case params do
      %{"leave" => "true"} ->
        socket = MarskalWeb.Inspector.select(socket, "task", task.id)

        case params["focus"] do
          focus when is_binary(focus) and focus != "" ->
            push_event(socket, "inspector-focus", %{id: focus})

          _none ->
            socket
        end

      _params ->
        socket
    end
  end

  # The field's title and the inspector's copy stay the same string. A
  # draft opens once there is text, so a field focused on load does not
  # open the inspector.
  defp handle_event("draft-title", %{"title" => title} = params, socket) do
    case {socket.assigns.draft, params["form"]} do
      {nil, nil} ->
        {:halt, socket}

      {nil, form} ->
        if String.trim(title) == "",
          do: {:halt, socket},
          else:
            {:halt,
             assign(
               socket,
               :draft,
               Map.merge(socket.assigns.draft_place, %{title: title, form: form})
             )}

      {draft, _form} ->
        socket = assign(socket, :draft, %{draft | title: title})
        {:halt, push_event(socket, "draft-title", %{form: draft.form, title: title})}
    end
  end

  # Enter in the inspector's copy: the add field's form saves the task.
  defp handle_event("draft-submit", %{"title" => title}, socket) do
    case socket.assigns.draft do
      nil -> {:halt, socket}
      draft -> {:halt, push_event(socket, "draft-submit", %{form: draft.form, title: title})}
    end
  end

  # Escape, the inspector's close, or leaving an empty title: nothing is
  # saved, and the field is cleared.
  defp handle_event("draft-cancel", _params, socket) do
    case socket.assigns.draft do
      nil ->
        {:halt, socket}

      draft ->
        {:halt, socket |> assign(:draft, nil) |> push_event("draft-clear", %{form: draft.form})}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
