defmodule Marskal.Imports.Problems do
  @moduledoc """
  What an import could not carry over, made easy to find and fix (ADR 0013).

  An adapter lists, on each task or project node, what Marskal has no
  place for yet, as `{problem, label, value}`. `mark/2` then gives the
  item a tag under "Import problems" for each kind, and puts what the user
  needs to fix it in a block at the end of its notes:

      ---
      Imported from OmniFocus:
      - Repeat: FREQ=WEEKLY;BYDAY=TU

  A title over `Marskal.Tasks.Task.title_max/0` is cut there, and the rest
  goes in the block. The block is never cut: notes that do not fit beside
  it are, and that item is tagged as having shortened notes.

  The tags and the block come out the same on every import, so the
  three-way merge on re-import drops them once Marskal can carry the
  field, and keeps them gone once the user has removed them.
  """

  alias Marskal.Imports.Graph
  alias Marskal.Imports.TagNode
  alias Marskal.Tasks.Task

  @parent "problem"
  @kinds [
    missing_recurrence: "Missing recurrence",
    missing_section: "Missing section",
    shortened_title: "Shortened title",
    shortened_notes: "Shortened notes"
  ]

  def mark(%Graph{} = graph, source_name) do
    projects = Enum.map(graph.projects, &settle(&1, source_name))
    tasks = Enum.map(graph.tasks, &settle(&1, source_name))

    used =
      (projects ++ tasks)
      |> Enum.flat_map(& &1.tag_source_ids)
      |> Enum.filter(&problem_tag?/1)
      |> MapSet.new()

    %{graph | projects: projects, tasks: tasks, tags: graph.tags ++ tag_nodes(used, graph.tags)}
  end

  def problem_tag?(source_id), do: String.starts_with?(source_id, @parent <> ":")

  defp settle(node, source_name) do
    {title, rest} = split(node.title, Task.title_max())

    problems =
      node.problems ++ if(rest, do: [{:shortened_title, "Title continued", rest}], else: [])

    {notes, cut?} = fit(node.notes, block(problems, source_name))

    kinds =
      problems
      |> Enum.map(&elem(&1, 0))
      |> Enum.concat(if cut?, do: [:shortened_notes], else: [])
      |> Enum.uniq()

    %{
      node
      | title: title,
        notes: notes,
        tag_source_ids: node.tag_source_ids ++ Enum.map(kinds, &tag_id/1)
    }
  end

  defp split(nil, _max), do: {nil, nil}

  defp split(text, max) do
    if String.length(text) > max,
      do: {String.slice(text, 0, max), String.slice(text, max..-1//1)},
      else: {text, nil}
  end

  defp block([], _source_name), do: nil

  defp block(problems, source_name) do
    lines = Enum.map(problems, fn {_kind, label, value} -> "- #{label}: #{one_line(value)}" end)
    Enum.join(["---", "Imported from #{source_name}:" | lines], "\n")
  end

  defp one_line(value), do: value |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()

  defp fit(notes, nil) do
    max = Task.notes_max()
    if length_of(notes) > max, do: {String.slice(notes, 0, max), true}, else: {notes, false}
  end

  defp fit(notes, block) do
    max = Task.notes_max()
    block = String.slice(block, 0, max)
    room = max - String.length(block) - 2

    cond do
      length_of(notes) == 0 -> {block, false}
      room <= 0 -> {block, true}
      String.length(notes) > room -> {String.slice(notes, 0, room) <> "\n\n" <> block, true}
      true -> {notes <> "\n\n" <> block, false}
    end
  end

  defp length_of(nil), do: 0
  defp length_of(text), do: String.length(text)

  defp tag_id(kind), do: @parent <> ":" <> (kind |> Atom.to_string() |> String.replace("_", "-"))

  # The parent goes after the source's own top-level tags.
  defp tag_nodes(used, source_tags) do
    if MapSet.size(used) == 0 do
      []
    else
      top_rank =
        source_tags
        |> Enum.filter(&is_nil(&1.parent_source_id))
        |> Enum.map(& &1.rank)
        |> Enum.max(fn -> 0 end)

      parent = %TagNode{
        source_id: @parent,
        name: "Import problems",
        state: "active",
        rank: top_rank + 1
      }

      children =
        for {{kind, name}, rank} <- Enum.with_index(@kinds),
            MapSet.member?(used, tag_id(kind)),
            do: %TagNode{
              source_id: tag_id(kind),
              name: name,
              parent_source_id: @parent,
              state: "active",
              rank: rank
            }

      [parent | children]
    end
  end
end
