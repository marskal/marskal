defmodule MarskalWeb.TaskList do
  @moduledoc """
  Assigns a task list with what `MarskalWeb.TaskComponents.list/1` shows
  about its tags: effective tags and unavailable ids (ADR 0005), and which
  tasks are deferred (ADR 0006).

  A task marked done or dropped while the page is open stays in its row
  until the user leaves the view, so a slip can be undone in place. A task
  that leaves the list for any other reason, such as a move or a new tag,
  goes at once. A new mount starts clean, and a view that changes mode
  resets with `reset_tasks/1`.
  """

  import Phoenix.Component, only: [assign: 3]

  def assign_tasks(socket, tasks) do
    user = socket.assigns.current_scope.user
    shown = socket.assigns[:tasks] || []
    tasks = merge(shown, tasks, lingering(user, shown, tasks))

    socket
    |> assign(:tasks, tasks)
    |> assign(:task_tags, annotate(user, tasks))
  end

  @doc """
  What a task list shows beside the titles: effective tags and the ids tag
  state makes unavailable (ADR 0005), and the deferred ids (ADR 0006).
  """
  def annotate(user, tasks) do
    user
    |> Marskal.Tags.annotate(tasks)
    |> Map.put(:deferred, Marskal.Tasks.deferred_ids(user, tasks))
  end

  @doc "Forgets the rows on screen, so the next `assign_tasks/2` shows only its own."
  def reset_tasks(socket), do: assign(socket, :tasks, [])

  @doc """
  The tasks in `shown` that are missing from `fresh` because they are now
  done or dropped, reloaded, by id.
  """
  def lingering(user, shown, fresh) do
    fresh_ids = MapSet.new(fresh, & &1.id)

    case for(task <- shown, task.id not in fresh_ids, do: task.id) do
      [] ->
        %{}

      ids ->
        for task <- Marskal.Tasks.get_tasks(user, ids),
            task.state != :to_do,
            into: %{},
            do: {task.id, task}
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
