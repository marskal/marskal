defmodule MarskalWeb.NavMoves do
  @moduledoc """
  The moves the `.NavOutline` hook sends (`MarskalWeb.NavOutline`): a drop,
  and the indent, outdent, and sibling keys, for folders, projects, and
  tags. Every signed-in page has the sidebar, so `MarskalWeb.Inspector`
  attaches this to all of them. A move goes through its context, and the
  change broadcast rebuilds the sidebar and the page's list.
  """

  use Gettext, backend: MarskalWeb.Gettext

  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3]

  alias Marskal.ProjectOutline
  alias Marskal.Tags

  @types %{"folder" => :folder, "project" => :project}

  @move_events ~w(nav-indent nav-outdent nav-up nav-down)

  # Nothing to indent under, out of, or past: the key does nothing.
  @no_ops [:first, :last, :top_level, :not_a_folder]

  def attach(socket), do: attach_hook(socket, :nav_moves, :handle_event, &handle_event/3)

  defp handle_event(event, %{"type" => type, "id" => id}, socket)
       when event in @move_events and is_binary(id) do
    user = socket.assigns.current_scope.user
    opts = [show: socket.assigns.visibility]

    result =
      case type do
        "tag" ->
          move_tag(event, user, id, command_id(), opts)

        type when is_map_key(@types, type) ->
          move_item(event, user, {@types[type], id}, command_id(), opts)

        _ ->
          {:error, :unknown_type}
      end

    {:halt, report(socket, result)}
  end

  # A drop: under `parent_id`, right after `after_id` (either may be nil).
  defp handle_event("nav-place", %{"type" => type, "id" => id} = params, socket)
       when is_binary(id) do
    user = socket.assigns.current_scope.user
    parent_id = params["parent_id"]

    result =
      case {type, params["after_type"]} do
        {"tag", after_type} when after_type in ["tag", nil] ->
          Tags.place_tag(user, id, parent_id, params["after_id"], command_id())

        {type, after_type}
        when is_map_key(@types, type) and (is_map_key(@types, after_type) or is_nil(after_type)) ->
          sibling = after_type && {@types[after_type], params["after_id"]}
          ProjectOutline.place(user, {@types[type], id}, parent_id, sibling, command_id())

        _ ->
          {:error, :unknown_type}
      end

    {:halt, report(socket, result)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp move_item("nav-indent", user, item, command_id, opts),
    do: ProjectOutline.indent(user, item, command_id, opts)

  defp move_item("nav-outdent", user, item, command_id, opts),
    do: ProjectOutline.outdent(user, item, command_id, opts)

  defp move_item("nav-up", user, item, command_id, opts),
    do: ProjectOutline.move_up(user, item, command_id, opts)

  defp move_item("nav-down", user, item, command_id, opts),
    do: ProjectOutline.move_down(user, item, command_id, opts)

  defp move_tag("nav-indent", user, id, command_id, opts),
    do: Tags.indent_tag(user, id, command_id, opts)

  defp move_tag("nav-outdent", user, id, command_id, _opts),
    do: Tags.outdent_tag(user, id, command_id)

  defp move_tag("nav-up", user, id, command_id, opts),
    do: Tags.move_tag_up(user, id, command_id, opts)

  defp move_tag("nav-down", user, id, command_id, opts),
    do: Tags.move_tag_down(user, id, command_id, opts)

  defp report(socket, {:ok, _record}), do: socket
  defp report(socket, {:error, reason}) when reason in @no_ops, do: socket

  defp report(socket, {:error, %Ecto.Changeset{errors: errors}}) do
    if Keyword.has_key?(errors, :name),
      do: put_flash(socket, :error, gettext("A tag with that name is already there.")),
      else: failed(socket)
  end

  defp report(socket, {:error, _reason}), do: failed(socket)

  defp failed(socket), do: put_flash(socket, :error, gettext("Could not move that there."))

  defp command_id, do: Ecto.UUID.generate(version: 7)
end
