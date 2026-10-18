defmodule MarskalWeb.Inspector do
  @moduledoc """
  Shared state for the signed-in pages: the inspector selection, the sidebar
  tree and its moves (`MarskalWeb.NavMoves`), and live updates.

  Each page subscribes to the user's change broadcasts. On a change the hook
  rebuilds the sidebar and bumps `:change_version`, which makes the inspector
  reload its record. The message then goes on to the page's own
  `handle_info/2`, if it has one, so the page can reload its list.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias Marskal.Changes
  alias Marskal.ProjectNav

  def selected?(type, id, %{type: type, id: id}), do: true
  def selected?(_type, _id, _selection), do: false

  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns.current_scope.user
    if connected?(socket), do: Changes.subscribe(user)

    {:cont,
     socket
     |> assign(:nav, ProjectNav.build(user))
     |> assign(:change_version, 0)
     |> attach_hook(:inspector_params, :handle_params, &on_params/3)
     |> attach_hook(:inspector_event, :handle_event, &on_event/3)
     |> attach_hook(:inspector_info, :handle_info, &on_info/2)
     |> MarskalWeb.NavMoves.attach()}
  end

  @selection_keys ~w(task project folder tag)

  defp on_params(params, uri, socket) do
    uri = URI.parse(uri)

    # Other query params, such as the open stream's ?unavailable=1, survive
    # opening and closing the inspector.
    page_query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.drop(@selection_keys)

    socket =
      socket
      |> assign(:inspector, selection(params))
      |> assign(:inspector_path, uri.path)
      |> assign(:inspector_page_query, page_query)

    # push_patch always asks the view for handle_params/3. A view that does not
    # define one must be halted here, or the patch crashes. Views that do
    # define it, such as the import page, still run after this hook.
    continue_if_defined(socket, :handle_params, 3)
  end

  # A selection the list keys make replaces the history entry, so moving
  # down a list does not leave one entry per row (ADR 0031).
  defp on_event("inspect", %{"type" => type, "id" => id} = params, socket)
       when type in @selection_keys and is_binary(id) do
    {:halt,
     push_patch(socket,
       to: query_path(socket, %{type => id}),
       replace: params["replace"] == true
     )}
  end

  defp on_event("close-inspector", _params, socket) do
    {:halt, push_patch(socket, to: query_path(socket, %{}))}
  end

  defp on_event(_event, _params, socket), do: {:cont, socket}

  defp on_info({:marskal_change, _type, _id}, socket) do
    socket
    |> assign(:nav, ProjectNav.build(socket.assigns.current_scope.user))
    |> assign(:change_version, socket.assigns.change_version + 1)
    |> continue_if_defined(:handle_info, 2)
  end

  # A component cannot set the page flash itself.
  defp on_info({:put_flash, kind, message}, socket),
    do: {:halt, put_flash(socket, kind, message)}

  defp on_info(_message, socket), do: {:cont, socket}

  defp continue_if_defined(socket, fun, arity) do
    if function_exported?(socket.view, fun, arity),
      do: {:cont, socket},
      else: {:halt, socket}
  end

  defp selection(params) do
    cond do
      id = present(params["task"]) -> %{type: :task, id: id}
      id = present(params["project"]) -> %{type: :project, id: id}
      id = present(params["folder"]) -> %{type: :folder, id: id}
      id = present(params["tag"]) -> %{type: :tag, id: id}
      true -> nil
    end
  end

  defp present(id) when is_binary(id) and id != "", do: id
  defp present(_), do: nil

  defp query_path(socket, selection) do
    case Map.merge(socket.assigns.inspector_page_query, selection) do
      query when query == %{} -> socket.assigns.inspector_path
      query -> socket.assigns.inspector_path <> "?" <> URI.encode_query(query)
    end
  end
end
