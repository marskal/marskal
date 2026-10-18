defmodule Marskal.Imports.TodoistAdapter do
  @moduledoc """
  Parses a Todoist API v1 sync snapshot into an import graph.

  The inbox project is not created; its tasks are inbox tasks. A nested
  project becomes a folder. A parent with no tasks of its own is only that
  folder. A parent that also has tasks keeps them in a project named
  "<name> tasks" inside the folder. A parent cycle is cut so the folders
  still form a tree. A Todoist due date is planned, and a deadline is
  due. A repeat in a form `Marskal.Imports.TodoistRecurrence` reads
  becomes a rule on the planned date. The section, and a repeat it cannot
  read, have no column: they stay in extras, and the task is marked for
  the user to fix (`Marskal.Imports.Problems`). Labels become tags. Completed-task
  history is not in the snapshot. Titles are Markdown: their links move
  to the URL (`Marskal.Imports.TitleLinks`).

  Source ids are prefixed with their kind so a project id cannot collide
  with a task id in `import_items`.
  """

  alias Marskal.Imports.Folder
  alias Marskal.Imports.Graph
  alias Marskal.Imports.Limits
  alias Marskal.Imports.Problems
  alias Marskal.Imports.ProjectNode
  alias Marskal.Imports.TagNode
  alias Marskal.Imports.TaskNode
  alias Marskal.Imports.TitleLinks
  alias Marskal.Imports.TodoistRecurrence

  def parse(payload) when is_binary(payload) do
    snapshot =
      case Jason.decode(payload) do
        {:ok, %{} = snapshot} -> snapshot
        _ -> raise ArgumentError, "This Todoist snapshot could not be read."
      end

    limits = %Limits{}
    folders = list(snapshot, "folders")
    projects = list(snapshot, "projects")
    items = list(snapshot, "items")
    labels = list(snapshot, "labels")
    sections = list(snapshot, "sections")

    if length(folders) + length(projects) + length(items) + length(labels) > limits.records do
      raise ArgumentError, "Todoist snapshot has too many items."
    end

    inbox = inbox_ids(projects, snapshot["user"])
    section_names = section_names(sections)
    {tag_nodes, label_ids} = tags(labels, items)
    {folder_nodes, project_nodes} = structure(folders, projects, items, inbox)
    project_ids = MapSet.new(project_nodes, & &1.source_id)

    %Graph{
      source: "todoist",
      folders: folder_nodes,
      projects: project_nodes,
      tags: tag_nodes,
      tasks:
        items
        |> Enum.reject(&deleted?/1)
        |> sort_by("child_order", "content")
        |> Enum.flat_map(&task_node(&1, inbox, project_ids, section_names, label_ids))
    }
    |> Problems.mark("Todoist")
  end

  def parse(_payload), do: raise(ArgumentError, "This Todoist snapshot could not be read.")

  # Workspace folders, then one folder per project that has sub-projects.
  # A project with its own tasks also keeps a project named "<name> tasks".
  defp structure(folder_rows, project_rows, items, inbox) do
    workspace_folders =
      folder_rows
      |> Enum.reject(&deleted?/1)
      |> sort_by("child_order", "name")
      |> Enum.map(&workspace_folder/1)

    live =
      project_rows
      |> Enum.reject(&(deleted?(&1) or MapSet.member?(inbox, string_id(&1["id"]))))

    by_id = Map.new(live, fn row -> {string_id(row["id"]), row} end)
    parents = acyclic_parents(by_id)

    containers =
      parents
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    with_tasks =
      items
      |> Enum.reject(&deleted?/1)
      |> MapSet.new(&string_id(&1["project_id"]))
      |> MapSet.delete(nil)

    project_folders =
      live
      |> Enum.filter(&MapSet.member?(containers, string_id(&1["id"])))
      |> sort_by("child_order", "name")
      |> Enum.map(&project_folder(&1, parents, with_tasks))

    projects =
      live
      |> sort_by("child_order", "name")
      |> Enum.flat_map(&project_node(&1, containers, parents, with_tasks))

    {workspace_folders ++ project_folders, projects}
  end

  defp workspace_folder(row) do
    %Folder{
      source_id: source_id("folder", row["id"]),
      name: blank(row["name"], "Untitled folder"),
      parent_source_id: source_id("folder", row["parent_id"]),
      dropped: false,
      rank: order_rank(row["child_order"]),
      extras: %{}
    }
  end

  defp project_folder(row, parents, with_tasks) do
    id = string_id(row["id"])
    state = project_state(row)
    tasks? = MapSet.member?(with_tasks, id)
    {name, url, _more} = row["name"] |> blank("Untitled") |> TitleLinks.split()

    %Folder{
      source_id: project_folder_id(id),
      name: name,
      parent_source_id: placed_folder(id, row, parents),
      dropped: state == "dropped",
      rank: order_rank(row["child_order"]),
      extras:
        %{}
        |> put_extra("order_key", row["order_key"])
        |> put_extra("url", if(not tasks?, do: url))
        |> put_extra("notes", if(not tasks?, do: text(row["description"])))
        |> put_extra("defer", if(not tasks? && row["status"] == "PAUSED", do: "indefinite"))
        |> put_flag("shared", not tasks? && row["shared"] == true)
        |> put_extra("state", if(not tasks? && state == "done", do: "done"))
    }
    |> with_problems()
  end

  # What a folder cannot hold, named in the import summary.
  defp with_problems(%Folder{extras: extras} = folder) do
    problems =
      for {key, label} <- [
            {"notes", "Notes"},
            {"url", "URL"},
            {"defer", "Paused"},
            {"state", "Completed"}
          ],
          Map.has_key?(extras, key),
          do: label

    %{folder | problems: problems}
  end

  defp project_node(row, containers, parents, with_tasks) do
    id = string_id(row["id"])
    {name, url, more} = row["name"] |> blank("Untitled") |> TitleLinks.split()
    notes = TitleLinks.notes(text(row["description"]), more)
    container? = MapSet.member?(containers, id)

    cond do
      container? and not MapSet.member?(with_tasks, id) ->
        []

      container? ->
        [
          %ProjectNode{
            source_id: source_id("project", id),
            title: tasks_title(name),
            notes: notes,
            url: url,
            folder_source_id: project_folder_id(id),
            state: project_state(row),
            # First in its folder, above the sub-projects, as in Todoist.
            rank: -1,
            extras: project_extras(row)
          }
        ]

      true ->
        [
          %ProjectNode{
            source_id: source_id("project", id),
            title: name,
            notes: notes,
            url: url,
            folder_source_id: placed_folder(id, row, parents),
            state: project_state(row),
            rank: order_rank(row["child_order"]),
            extras: project_extras(row)
          }
        ]
    end
  end

  # Inside the parent project's folder when there is one, otherwise the
  # workspace folder Todoist filed this project in.
  defp placed_folder(id, row, parents) do
    case Map.get(parents, id) do
      nil -> source_id("folder", row["folder_id"])
      parent_id -> project_folder_id(parent_id)
    end
  end

  defp project_extras(row) do
    %{}
    |> put_extra("order_key", row["order_key"])
    |> put_extra("defer", if(row["status"] == "PAUSED", do: "indefinite"))
    |> put_flag("shared", row["shared"])
  end

  defp tasks_title(name), do: String.slice(name, 0, 494) <> " tasks"

  defp project_folder_id(id), do: "folder:project:" <> id

  # child id => parent id, with a back edge dropped so the folders form a tree.
  defp acyclic_parents(by_id) do
    proposed =
      Map.new(by_id, fn {id, row} ->
        parent = string_id(row["parent_id"])
        {id, if(parent != id && Map.has_key?(by_id, parent || ""), do: parent, else: nil)}
      end)

    {accepted, _done} =
      proposed
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce({%{}, MapSet.new()}, fn id, {accepted, done} ->
        visit_parent(id, proposed, accepted, done, MapSet.new())
      end)

    accepted
  end

  defp visit_parent(id, proposed, accepted, done, stack) do
    if Map.has_key?(accepted, id) or MapSet.member?(done, id) do
      {accepted, done}
    else
      accept_parent(id, proposed, accepted, done, stack)
    end
  end

  defp accept_parent(id, proposed, accepted, done, stack) do
    parent = Map.get(proposed, id)
    valid? = is_binary(parent) and parent != id and not MapSet.member?(stack, parent)

    {accepted, done} =
      if valid? do
        visit_parent(parent, proposed, accepted, done, MapSet.put(stack, id))
      else
        {accepted, done}
      end

    {Map.put(accepted, id, if(valid?, do: parent)), MapSet.put(done, id)}
  end

  defp task_node(row, inbox, project_ids, section_names, label_ids) do
    project_source_id = source_id("project", row["project_id"])
    inbox? = MapSet.member?(inbox, string_id(row["project_id"]))

    cond do
      inbox? ->
        [task(row, true, nil, section_names, label_ids)]

      project_source_id in project_ids ->
        [task(row, false, project_source_id, section_names, label_ids)]

      true ->
        []
    end
  end

  defp task(row, inbox?, project_source_id, section_names, label_ids) do
    parent = source_id("task", row["parent_id"])
    section = section_names[string_id(row["section_id"])]
    repeat = repeat(row["due"])
    recurrence = recurrence(repeat, row["due"])
    names = label_names(row)
    {title, url, more} = row["content"] |> blank("Untitled") |> TitleLinks.split()

    %TaskNode{
      source_id: source_id("task", row["id"]),
      title: title,
      notes: row["description"] |> text() |> TitleLinks.notes(more),
      url: url,
      inbox: inbox?,
      project_source_id: project_source_id,
      parent_source_id: parent,
      flagged: row["priority"] == 4,
      state: if(done?(row), do: "done", else: "to_do"),
      planned: date_value(row["due"]),
      due: date_value(row["deadline"]),
      resolved_at: if(done?(row), do: row["completed_at"]),
      recurrence: recurrence,
      tag_source_ids:
        names |> Enum.map(&label_ids[tag_key(&1)]) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      extras:
        %{}
        |> put_extra("section", section)
        |> put_extra("order_key", row["order_key"])
        |> put_extra("planned_zone", get_in(row, ["due", "timezone"]))
        |> put_extra("repeat", repeat),
      problems:
        Enum.reject(
          [
            repeat && is_nil(recurrence) && {:missing_recurrence, "Repeat", repeat},
            section && {:missing_section, "Section", section}
          ],
          &(&1 in [nil, false])
        )
    }
  end

  defp tags(labels, items) do
    personal =
      labels
      |> Enum.reject(&deleted?/1)
      |> sort_by("item_order", "name")
      |> Enum.flat_map(fn row ->
        case tag_name(row["name"]) do
          "" ->
            []

          name ->
            [%TagNode{source_id: source_id("tag", row["id"]), name: name, state: "active"}]
        end
      end)

    known =
      Map.new(personal, fn tag -> {tag_key(tag.name), tag.name} end)

    shared =
      items
      |> Enum.reject(&deleted?/1)
      |> Enum.flat_map(&label_names/1)
      |> Enum.map(&tag_name/1)
      |> Enum.reject(&(&1 == "" or Map.has_key?(known, tag_key(&1))))
      |> Enum.uniq_by(&tag_key/1)
      |> Enum.sort()
      |> Enum.map(fn name ->
        %TagNode{source_id: "tag:shared:" <> tag_key(name), name: name, state: "active"}
      end)

    # Labels are flat, so every tag is top level, in label order.
    nodes =
      (personal ++ shared)
      |> Enum.with_index()
      |> Enum.map(fn {tag, rank} -> %{tag | rank: rank} end)

    {nodes, Map.new(nodes, &{tag_key(&1.name), &1.source_id})}
  end

  # A task's labels, and the tag that keeps a P2 or P3 priority (ADR 0025).
  # The API counts priority up: 4 is P1, which flags the task, and 1 is P4.
  defp label_names(row) do
    names = row |> Map.get("labels", []) |> List.wrap() |> Enum.filter(&is_binary/1)

    case row["priority"] do
      3 -> names ++ ["Priority 2"]
      2 -> names ++ ["Priority 3"]
      _ -> names
    end
  end

  defp section_names(sections) do
    Map.new(sections, fn row ->
      name = if deleted?(row), do: nil, else: text(row["name"])
      {string_id(row["id"]), name}
    end)
  end

  defp inbox_ids(projects, user) do
    ids =
      for project <- projects, project["inbox_project"] == true, id = string_id(project["id"]) do
        id
      end

    user_inbox =
      case user do
        %{"inbox_project_id" => id} -> string_id(id)
        _ -> nil
      end

    [user_inbox | ids] |> MapSet.new() |> MapSet.delete(nil)
  end

  defp project_state(row) do
    cond do
      row["is_archived"] == true -> "dropped"
      row["status"] == "COMPLETED" -> "done"
      row["status"] in ["CANCELED", "CANCELLED"] -> "dropped"
      true -> "to_do"
    end
  end

  defp done?(row), do: row["checked"] == true or present?(row["completed_at"])

  defp deleted?(row), do: row["is_deleted"] == true

  defp date_value(value) when is_map(value) do
    case value["date"] do
      date when is_binary(date) and date != "" -> date
      _ -> nil
    end
  end

  defp date_value(_value), do: nil

  defp repeat(%{"is_recurring" => true, "string" => string})
       when is_binary(string) and string != "",
       do: string

  defp repeat(_due), do: nil

  # A rule needs the date it moves; a repeat with no date stays a problem.
  defp recurrence(nil, _due), do: nil

  defp recurrence(repeat, due) do
    with date when is_binary(date) <- date_value(due),
         {:ok, rule} <- TodoistRecurrence.parse(repeat) do
      rule
    else
      _ -> nil
    end
  end

  defp put_flag(extras, _key, value) when value in [nil, false], do: extras
  defp put_flag(extras, key, true), do: Map.put(extras, key, true)

  defp put_extra(extras, _key, value) when value in [nil, ""], do: extras
  defp put_extra(extras, key, value), do: Map.put(extras, key, value)

  defp list(snapshot, key) do
    case Map.get(snapshot, key) do
      rows when is_list(rows) -> Enum.filter(rows, &is_map/1)
      _ -> []
    end
  end

  defp sort_by(rows, order_key, label_key) do
    Enum.sort_by(rows, fn row ->
      {order_rank(row[order_key]), row[label_key] || ""}
    end)
  end

  defp order_rank(number) when is_integer(number), do: number
  defp order_rank(_number), do: 1_000_000_000

  defp source_id(_kind, id) when id in [nil, ""], do: nil

  defp source_id(kind, id) do
    case string_id(id) do
      nil -> nil
      value -> kind <> ":" <> value
    end
  end

  defp string_id(id) when is_binary(id) and id != "", do: id
  defp string_id(id) when is_integer(id), do: Integer.to_string(id)
  defp string_id(_id), do: nil

  defp blank(value, fallback) do
    case text(value) do
      nil -> fallback
      title -> title
    end
  end

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp text(_value), do: nil

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false

  # Tag names match ignoring case, so a label's key is its lowercased name.
  defp tag_name(name) when is_binary(name) do
    name |> String.trim() |> String.normalize(:nfc) |> String.slice(0, 200)
  end

  defp tag_name(_name), do: ""

  defp tag_key(name), do: name |> tag_name() |> String.downcase()
end
