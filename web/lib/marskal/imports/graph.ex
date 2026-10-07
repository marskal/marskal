defmodule Marskal.Imports.Graph do
  @moduledoc false

  defstruct [:source, folders: [], projects: [], tasks: [], tags: []]

  @folder_samples 50

  def stats(%__MODULE__{} = graph) do
    samples =
      (Enum.map(graph.projects, & &1.title) ++ Enum.map(graph.tasks, & &1.title))
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.take(8)

    %{
      "folders" => length(graph.folders),
      "projects" => length(graph.projects),
      "tasks" => length(graph.tasks),
      "tags" => length(graph.tags),
      "inbox" => Enum.count(graph.tasks, & &1.inbox),
      "samples" => samples,
      "problems" =>
        Enum.count(graph.projects ++ graph.tasks, fn node ->
          Enum.any?(node.tag_source_ids, &Marskal.Imports.Problems.problem_tag?/1)
        end),
      "folder_problems" =>
        for(
          folder <- graph.folders,
          folder.problems != [],
          do: %{"name" => folder.name, "fields" => folder.problems}
        )
        |> Enum.take(@folder_samples)
    }
  end
end
