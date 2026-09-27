defmodule Marskal.Imports.OmnifocusAdapter do
  @moduledoc false

  alias Marskal.Imports.Folder
  alias Marskal.Imports.Graph
  alias Marskal.Imports.Limits
  alias Marskal.Imports.OmnifocusNote
  alias Marskal.Imports.ProjectNode
  alias Marskal.Imports.TagNode
  alias Marskal.Imports.TaskNode
  alias Marskal.Imports.Xml

  @source "omnifocus"
  @inner_zip ~r/\.zip\z/i
  @master_prefix "00000000000000="
  @merge_name ~r/\A[^=]+=[^=+]+\+[^=+]+\+[^=+]+\.zip\z/i

  def key, do: @source

  def match?(bytes, filename) when is_binary(bytes) do
    name = String.downcase(filename || "")

    cond do
      String.ends_with?(name, ".ofocus-backup") or String.ends_with?(name, ".ofocus") ->
        true

      not zip?(bytes) ->
        false

      true ->
        entries(bytes) |> Enum.any?(&inner_package_entry?/1)
    end
  rescue
    ArgumentError -> false
  end

  def parse(bytes, opts \\ []) when is_binary(bytes) do
    limits = Keyword.get(opts, :limits, %Limits{})

    unless zip?(bytes) do
      raise ArgumentError,
            "This looks like an OmniFocus package, not a zip. In Finder, compress the .ofocus-backup (it is a folder), or in the Export save panel choose File Format → Backup Document, then upload that file."
    end

    documents = xml_documents(bytes, limits)
    if documents == [], do: raise(ArgumentError, "No OmniFocus contents.xml found in the backup.")

    stores =
      Enum.reduce(documents, %{folders: %{}, tasks: %{}, tags: %{}, links: %{}}, fn xml, stores ->
        apply_document(xml, stores, limits)
      end)

    tag_ids = tag_ids_by_task(stores)

    %Graph{
      source: @source,
      folders: folder_nodes(stores.folders),
      projects: project_nodes(stores.tasks, tag_ids),
      tasks: task_nodes(stores.tasks, tag_ids),
      tags: tag_nodes(stores.tags)
    }
  end

  defp zip?(bytes), do: String.starts_with?(bytes, "PK\x03\x04")

  defp entries(bytes) do
    case :zip.unzip(bytes, [:memory]) do
      {:ok, list} ->
        Enum.map(list, fn {name, data} -> {to_string(name), data} end)

      {:error, _} ->
        raise ArgumentError, "The backup zip could not be read."
    end
  end

  defp inner_package_entry?({name, _data}) do
    base = Path.basename(name)
    not String.contains?(name, "..") and (base =~ @inner_zip or base == "contents.xml")
  end

  defp xml_documents(bytes, limits) do
    list = entries(bytes)

    if length(list) > limits.zip_entries,
      do: raise(ArgumentError, "Backup has too many zip entries.")

    {docs, _inflated, _inner} =
      Enum.reduce(list, {[], 0, 0}, fn {name, data}, {docs, inflated, inner_zips} ->
        assert_safe!(name)
        base = Path.basename(name)

        cond do
          String.ends_with?(name, "/") or base =~ @merge_name or
              String.ends_with?(base, ".client") ->
            {docs, inflated, inner_zips}

          base == "contents.xml" ->
            xml = cap!(data, limits.xml_bytes, inflated, limits)
            {[{sort_key(base), xml} | docs], inflated + byte_size(data), inner_zips}

          base =~ @inner_zip ->
            inner_zips = inner_zips + 1

            if inner_zips > limits.inner_zips,
              do: raise(ArgumentError, "Backup has too many nested zips.")

            data = cap!(data, limits.entry_bytes, inflated, limits)

            case xml_from_inner_zip(data, limits) do
              nil -> {docs, inflated + byte_size(data), inner_zips}
              xml -> {[{sort_key(base), xml} | docs], inflated + byte_size(data), inner_zips}
            end

          true ->
            {docs, inflated, inner_zips}
        end
      end)

    docs |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
  end

  defp xml_from_inner_zip(bytes, limits) do
    list = entries(bytes)

    if length(list) > limits.zip_entries,
      do: raise(ArgumentError, "Backup has too many zip entries.")

    Enum.find_value(list, fn {name, data} ->
      assert_safe!(name)

      if Path.basename(name) == "contents.xml" do
        if byte_size(data) > limits.xml_bytes,
          do: raise(ArgumentError, "Backup XML is too large.")

        data
      end
    end)
  rescue
    error in ArgumentError -> reraise error, __STACKTRACE__
    _ -> nil
  end

  defp assert_safe!(name) do
    if String.contains?(name, "..") or String.starts_with?(name, "/") do
      raise ArgumentError, "Unsafe zip entry #{name}"
    end
  end

  defp cap!(data, cap, inflated, limits) do
    if byte_size(data) > cap or inflated + byte_size(data) > limits.inflated_bytes do
      raise ArgumentError, "Backup expands beyond the allowed size."
    end

    data
  end

  defp sort_key(basename) do
    if String.starts_with?(basename, @master_prefix) or basename == "contents.xml" do
      {0, ""}
    else
      {1, basename |> String.split("=", parts: 2) |> hd()}
    end
  end

  # Tags are <context> records; <task-to-tag> records link a task (or a
  # project, which is a task) to one.
  @records %{
    "folder" => :folders,
    "task" => :tasks,
    "context" => :tags,
    "task-to-tag" => :links
  }

  defp apply_document(xml, stores, limits) do
    doc = Xml.parse!(xml)
    unless Xml.name(doc) == "omnifocus", do: raise(ArgumentError, "Not an OmniFocus backup.")

    Enum.reduce(Xml.children(doc), stores, fn element, stores ->
      if stores |> Map.values() |> Enum.map(&map_size/1) |> Enum.sum() > limits.records do
        raise ArgumentError, "Backup has too many items."
      end

      case Map.fetch(@records, Xml.name(element)) do
        {:ok, store} ->
          Map.update!(stores, store, &apply_record(&1, element, parser(store, limits)))

        :error ->
          stores
      end
    end)
  end

  defp parser(:folders, limits), do: &parse_folder(&1, limits)
  defp parser(:tasks, limits), do: &parse_task(&1, limits)
  defp parser(:tags, limits), do: &parse_tag(&1, limits)
  defp parser(:links, _limits), do: &parse_link/1

  defp apply_record(store, element, parser) do
    id = Xml.attr(element, "id")
    if id in [nil, ""], do: store, else: apply_op(store, element, id, parser)
  end

  defp apply_op(store, element, id, parser) do
    case Xml.attr(element, "op") do
      "reference" ->
        Map.put_new_lazy(store, id, fn -> parser.(element) end)

      "delete" ->
        Map.delete(store, id)

      _ ->
        incoming = parser.(element)

        Map.update(store, id, incoming, fn old ->
          Map.merge(old, incoming, fn _key, old_val, new_val ->
            if is_nil(new_val), do: old_val, else: new_val
          end)
        end)
    end
  end

  defp parse_folder(element, limits) do
    parent =
      element
      |> Xml.children_named("folder")
      |> Enum.find(&(Xml.attr(&1, "idref") not in [nil, ""]))

    %{
      "id" => Xml.attr(element, "id"),
      "name" => clip(text_at(element, "name"), limits.title_chars),
      "parent_id" => parent && Xml.attr(parent, "idref"),
      "hidden" => text_at(element, "hidden") == "true"
    }
  end

  defp parse_tag(element, limits) do
    parent =
      element
      |> Xml.children_named("context")
      |> Enum.find(&(Xml.attr(&1, "idref") not in [nil, ""]))

    %{
      "id" => Xml.attr(element, "id"),
      "name" => clip(text_at(element, "name"), limits.title_chars),
      "parent_id" => parent && Xml.attr(parent, "idref"),
      "rank" => text_at(element, "rank"),
      "hidden" => text_at(element, "hidden"),
      "on_hold" => text_at(element, "prohibits-next-action")
    }
  end

  defp parse_link(element) do
    %{
      "task_id" => element |> Xml.child("task") |> idref(),
      "tag_id" => element |> Xml.child("context") |> idref()
    }
  end

  defp idref(nil), do: nil
  defp idref(element), do: Xml.attr(element, "idref")

  defp parse_task(element, limits) do
    parent =
      element
      |> Xml.children_named("task")
      |> Enum.find(&(Xml.attr(&1, "idref") not in [nil, ""]))

    %{
      "id" => Xml.attr(element, "id"),
      "name" => clip(text_at(element, "name"), limits.title_chars),
      "notes" => notes_at(element, limits),
      "inbox" => inbox?(element),
      "parent_id" => parent && Xml.attr(parent, "idref"),
      "completed" => text_at(element, "completed"),
      "start" => text_at(element, "start"),
      "due" => text_at(element, "due"),
      "planned" => text_at(element, "planned"),
      "flagged" => text_at(element, "flagged") == "true",
      "repeat" => text_at(element, "repeat") || text_at(element, "repetition-rule"),
      "project" => project_info(element),
      "tag_ids" => tag_ids(element)
    }
  end

  defp inbox?(element) do
    case Xml.child(element, "inbox") do
      nil -> false
      node -> Xml.text(node) in [nil, "", "true"]
    end
  end

  defp project_info(element) do
    case Xml.child(element, "project") do
      nil ->
        nil

      project ->
        if Xml.children(project) == [] do
          nil
        else
          folder = project |> Xml.children_named("folder") |> List.first()

          %{
            "folder_id" => folder && Xml.attr(folder, "idref"),
            "status" => text_at(project, "status") || "active"
          }
        end
    end
  end

  defp tag_ids(element) do
    (Xml.children_named(element, "tag") ++ Xml.children_named(element, "context"))
    |> Enum.map(&Xml.attr(&1, "idref"))
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp text_at(element, child_name) do
    case Xml.child(element, child_name) do
      nil -> nil
      child -> Xml.text(child)
    end
  end

  defp notes_at(element, limits) do
    case Xml.child(element, "note") do
      nil -> nil
      note -> clip(OmnifocusNote.to_markdown(note), limits.notes_chars)
    end
  end

  defp clip(nil, _max), do: nil
  defp clip("", _max), do: nil

  defp clip(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max), else: text
  end

  defp folder_nodes(folders) do
    Enum.map(folders, fn {_id, row} ->
      %Folder{
        source_id: row["id"],
        name: row["name"] || "Untitled folder",
        parent_source_id: row["parent_id"],
        dropped: row["hidden"] == true,
        extras: %{}
      }
    end)
  end

  # Hidden means dropped; prohibits-next-action means on hold.
  defp tag_nodes(tags) do
    Enum.map(tags, fn {_id, row} ->
      %TagNode{
        source_id: row["id"],
        name: row["name"] || "Untitled tag",
        parent_source_id: if(Map.has_key?(tags, row["parent_id"]), do: row["parent_id"]),
        state:
          cond do
            row["hidden"] == "true" -> "dropped"
            row["on_hold"] == "true" -> "on_hold"
            true -> "active"
          end,
        rank: parse_rank(row["rank"])
      }
    end)
  end

  defp parse_rank(nil), do: 0

  defp parse_rank(text) do
    case Integer.parse(text) do
      {rank, _} -> rank
      :error -> 0
    end
  end

  # A task's tags: the ones named on the task itself, then those from
  # task-to-tag records, keeping only tags the backup defines.
  defp tag_ids_by_task(stores) do
    linked =
      stores.links
      |> Map.values()
      |> Enum.group_by(& &1["task_id"], & &1["tag_id"])

    Map.new(stores.tasks, fn {id, row} ->
      ids =
        ((row["tag_ids"] || []) ++ Map.get(linked, id, []))
        |> Enum.filter(&Map.has_key?(stores.tags, &1))
        |> Enum.uniq()

      {id, ids}
    end)
  end

  defp project_nodes(tasks, tag_ids) do
    tasks
    |> Map.values()
    |> Enum.flat_map(fn row ->
      if row["project"] do
        [
          %ProjectNode{
            source_id: row["id"],
            title: row["name"] || "Untitled project",
            notes: row["notes"],
            folder_source_id: row["project"]["folder_id"],
            state: project_state(row["project"]["status"], row["completed"]),
            tag_source_ids: Map.get(tag_ids, row["id"], []),
            extras: extras_for(row)
          }
        ]
      else
        []
      end
    end)
  end

  defp task_nodes(tasks, tag_ids) do
    project_ids =
      tasks
      |> Map.values()
      |> Enum.flat_map(fn row -> if row["project"], do: [row["id"]], else: [] end)
      |> MapSet.new()

    tasks
    |> Map.values()
    |> Enum.flat_map(fn row ->
      if row["project"] do
        []
      else
        {project_id, parent_id} = resolve_project(row, tasks, project_ids)
        # A task in a project is in that project, even if the backup also
        # flags it inbox; one without a project is in the inbox (ADR 0017).
        inbox = is_nil(project_id)

        [
          %TaskNode{
            source_id: row["id"],
            title: row["name"] || "Untitled task",
            notes: row["notes"],
            inbox: inbox,
            project_source_id: project_id,
            parent_source_id: parent_id,
            state: task_state(row),
            tag_source_ids: Map.get(tag_ids, row["id"], []),
            extras: extras_for(row) |> Map.put("parent_source_id", parent_id) |> compact()
          }
        ]
      end
    end)
  end

  defp resolve_project(row, tasks, project_ids) do
    parent_id = row["parent_id"]
    walk(parent_id, tasks, project_ids, MapSet.new(), parent_id)
  end

  defp walk(nil, _tasks, _project_ids, _seen, parent_id), do: {nil, parent_id}

  defp walk(walker, tasks, project_ids, seen, parent_id) do
    cond do
      not MapSet.member?(seen, walker) and MapSet.member?(project_ids, walker) ->
        {walker, parent_id}

      MapSet.member?(seen, walker) ->
        {nil, parent_id}

      true ->
        walk(
          get_in(tasks, [walker, "parent_id"]),
          tasks,
          project_ids,
          MapSet.put(seen, walker),
          parent_id
        )
    end
  end

  defp project_state(status, completed) do
    cond do
      is_binary(completed) and completed != "" -> "done"
      status == "done" -> "done"
      status == "dropped" -> "dropped"
      true -> "to_do"
    end
  end

  defp task_state(row) do
    cond do
      is_binary(row["completed"]) and row["completed"] != "" -> "done"
      get_in(row, ["project", "status"]) == "dropped" -> "dropped"
      true -> "to_do"
    end
  end

  defp extras_for(row) do
    %{}
    |> put_extra("defer_until", row["start"])
    |> put_extra("due", row["due"])
    |> put_extra("planned", row["planned"])
    |> then(fn extras ->
      if row["flagged"], do: Map.put(extras, "flagged", true), else: extras
    end)
    |> put_extra("repeat", row["repeat"])
    |> then(fn extras ->
      if get_in(row, ["project", "status"]) == "inactive",
        do: Map.put(extras, "defer", "indefinite"),
        else: extras
    end)
  end

  defp put_extra(extras, _key, value) when value in [nil, ""], do: extras
  defp put_extra(extras, key, value), do: Map.put(extras, key, value)

  defp compact(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)
end
