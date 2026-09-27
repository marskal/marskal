defmodule MarskalWeb.TaskList do
  @moduledoc """
  Assigns a task list with what `MarskalWeb.TaskComponents.list/1` shows
  about its tags: effective tags and unavailable ids (ADR 0005).

  A task that leaves the list while the page is open, because it was done,
  dropped, moved, or edited, stays in its row until the user leaves the
  view. That leaves room to undo a slip without going elsewhere. A new mount
  starts clean, and a view that changes mode resets with `reset_tasks/1`.
  """

  import Phoenix.Component, only: [assign: 3]

  def assign_tasks(socket, tasks) do
    user = socket.assigns.current_scope.user
    shown = socket.assigns[:tasks] || []
    tasks = merge(shown, tasks, lingering(user, shown, tasks))

    socket
    |> assign(:tasks, tasks)
    |> assign(:task_tags, Marskal.Tags.annotate(user, tasks))
  end

  @doc "Forgets the rows on screen, so the next `assign_tasks/2` shows only its own."
  def reset_tasks(socket), do: assign(socket, :tasks, [])

  @doc """
  The tasks in `shown` that are missing from `fresh`, reloaded, by id.
  """
  def lingering(user, shown, fresh) do
    fresh_ids = MapSet.new(fresh, & &1.id)

    case for(task <- shown, task.id not in fresh_ids, do: task.id) do
      [] -> %{}
      ids -> user |> Marskal.Tasks.get_tasks(ids) |> Map.new(&{&1.id, &1})
    end
  end

  @doc """
  `fresh`, with each item from `lingering` put back after the row it
  followed in `shown`. Items match by `id_fun`.
  """
  def merge(shown, fresh, lingering, id_fun \\ & &1.id)

  def merge(_shown, fresh, lingering, _id_fun) when lingering == %{}, do: fresh

  def merge(shown, fresh, lingering, id_fun) do
    fresh_ids = MapSet.new(fresh, id_fun)

    {after_row, _anchor} =
      Enum.reduce(shown, {%{}, :top}, fn item, {acc, anchor} ->
        id = id_fun.(item)

        cond do
          kept = lingering[id] -> {Map.update(acc, anchor, [kept], &[kept | &1]), anchor}
          id in fresh_ids -> {acc, id}
          true -> {acc, anchor}
        end
      end)

    following = fn anchor -> after_row |> Map.get(anchor, []) |> Enum.reverse() end
    following.(:top) ++ Enum.flat_map(fresh, &[&1 | following.(id_fun.(&1))])
  end
end
