defmodule Marskal.Imports.Graph do
  @moduledoc false

  defstruct [:source, folders: [], projects: [], tasks: []]

  def stats(%__MODULE__{} = graph) do
    samples =
      (Enum.map(graph.projects, & &1.title) ++ Enum.map(graph.tasks, & &1.title))
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.take(8)

    %{
      "folders" => length(graph.folders),
      "projects" => length(graph.projects),
      "tasks" => length(graph.tasks),
      "inbox" => Enum.count(graph.tasks, & &1.inbox),
      "samples" => samples
    }
  end
end
