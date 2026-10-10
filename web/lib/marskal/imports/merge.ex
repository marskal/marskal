defmodule Marskal.Imports.Merge do
  @moduledoc """
  The three-way merge of a re-import (ADR 0013): the base is what the
  source said last time, the current value is the user's, and the incoming
  one is what the source says now.

  A field the source changed is taken unless the user changed it too; then
  the user's value stays and the field is reported as kept. Fields that
  move together, such as a location, merge as one group. Values are as the
  change feed encodes them.
  """

  alias Marskal.Changes

  @groups %{
    task: [
      ~w(title),
      ~w(notes),
      ~w(url),
      ~w(flagged),
      ~w(state),
      ~w(inbox project_id),
      ~w(parent_id),
      ~w(defer_until deferred_indefinitely),
      ~w(planned_at),
      ~w(due_at)
    ],
    project: [
      ~w(title),
      ~w(notes),
      ~w(url),
      ~w(flagged),
      ~w(state),
      ~w(project_folder_id),
      ~w(defer_until deferred_indefinitely),
      ~w(planned_at),
      ~w(due_at)
    ],
    folder: [~w(name), ~w(parent_id), ~w(state)],
    tag: [~w(name), ~w(parent_id), ~w(state)]
  }

  @schemas %{
    task: Marskal.Tasks.Task,
    project: Marskal.Projects.Project,
    folder: Marskal.ProjectFolders.ProjectFolder,
    tag: Marskal.Tags.Tag
  }

  def groups(kind), do: Map.fetch!(@groups, kind)

  def fields(kind), do: kind |> groups() |> List.flatten()

  @doc "A record's merged fields, encoded."
  def snapshot(kind, record) do
    Map.new(fields(kind), fn field ->
      {field, Changes.encode_value(Map.get(record, String.to_existing_atom(field)))}
    end)
  end

  @doc """
  `{patch, kept}`: the fields to write, and the first field of each group
  where the user's value stood against a change in the source.
  """
  def fields(kind, base, current, incoming) do
    Enum.reduce(groups(kind), {%{}, []}, fn group, {patch, kept} ->
      b = Map.take(Map.merge(defaults(kind), base), group)
      c = Map.take(current, group)
      i = Map.take(incoming, group)

      cond do
        i == b or i == c -> {patch, kept}
        c == b -> {Map.merge(patch, i), kept}
        true -> {patch, kept ++ [hd(group)]}
      end
    end)
  end

  # A field the base predates was not set then: it had its default.
  defp defaults(kind), do: snapshot(kind, struct(Map.fetch!(@schemas, kind)))

  @doc """
  `{add, remove}` for a set of tag ids. A tag the user added or removed
  stays as they left it.
  """
  def tags(base, current, incoming) do
    [base, current, incoming] = Enum.map([base, current, incoming], &MapSet.new/1)

    add = incoming |> MapSet.difference(base) |> MapSet.difference(current)
    remove = base |> MapSet.difference(incoming) |> MapSet.intersection(current)

    {Enum.sort(add), Enum.sort(remove)}
  end
end
