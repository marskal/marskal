defmodule Marskal.Imports.TaskpaperAdapter do
  @moduledoc """
  Parses a TaskPaper outline into an import graph (ADR 0013).

  A project named Inbox is the inbox. A task with no project is No project.
  `@folder`, or a colon line that holds projects and no tasks, is a project
  folder. A project inside a project is filed beside it.
  """

  alias Marskal.Dates
  alias Marskal.Imports.Folder
  alias Marskal.Imports.Graph
  alias Marskal.Imports.Limits
  alias Marskal.Imports.OmnifocusRecurrence
  alias Marskal.Imports.Problems
  alias Marskal.Imports.ProjectNode
  alias Marskal.Imports.TagNode
  alias Marskal.Imports.TaskNode
  alias Marskal.Imports.Taskpaper
  alias Marskal.Recurrence.Series
  alias Marskal.Url

  @source "taskpaper"
  @tag_max 200

  @reserved MapSet.new(~w(
    done dropped due defer start planned flagged url id folder tags
    autodone parallel estimate
    repeat-rule repeat-method repeat-schedule-type repeat-anchor-date repeat-catch-up
  ))

  @anchor_labels %{"due" => "Due", "defer" => "Defer", "planned" => "Planned"}

  def match?(bytes, filename) when is_binary(bytes) do
    cond do
      taskpaper_name?(filename) -> true
      zip?(bytes) -> false
      true -> Taskpaper.outline?(bytes)
    end
  end

  def match?(_bytes, filename), do: taskpaper_name?(filename)

  def parse(payload, opts \\ []) when is_binary(payload) do
    limits = Keyword.get(opts, :limits, %Limits{})
    {roots, skipped} = Taskpaper.parse(payload)

    acc =
      walk(roots, root_ctx(), %{
        folders: [],
        projects: [],
        tasks: [],
        tags: %{},
        tag_list: [],
        tag_rank: 0,
        skipped: skipped,
        count: 0,
        limits: limits
      })

    %Graph{
      source: @source,
      folders: last_wins(acc.folders),
      projects: last_wins(acc.projects),
      tasks: last_wins(acc.tasks),
      tags: Enum.reverse(acc.tag_list),
      skipped_rows: acc.skipped
    }
    |> Problems.mark("TaskPaper")
  end

  defp root_ctx do
    %{
      folder_id: nil,
      container: :root,
      container_title: nil,
      project_id: nil,
      project_title: nil,
      task_id: nil,
      inbox: false,
      path: [],
      nth: 0
    }
  end

  defp walk(items, ctx, acc) do
    items
    |> positioned()
    |> Enum.reduce(acc, fn {item, index, nth}, acc ->
      walk_item(item, %{ctx | nth: nth}, index, acc)
    end)
  end

  # Each item with its index, and how many siblings before it share its
  # kind and title. The index is the rank; the count goes in the identity.
  defp positioned(items) do
    items
    |> Enum.with_index()
    |> Enum.map_reduce(%{}, fn {item, index}, seen ->
      key = {item.type, title_key(item.text)}
      nth = Map.get(seen, key, 0)
      {{item, index, nth}, Map.put(seen, key, nth + 1)}
    end)
    |> elem(0)
  end

  defp title_key(text), do: text |> String.normalize(:nfc) |> String.trim()

  defp walk_item(%{type: :project} = item, ctx, index, acc) do
    cond do
      inbox_name?(item.text) -> walk_inbox(item, ctx, acc)
      folder?(item) -> walk_folder(item, ctx, index, acc)
      true -> walk_project(item, ctx, index, acc)
    end
  end

  defp walk_item(%{type: :task} = item, ctx, index, acc), do: walk_task(item, ctx, index, acc)

  defp walk_inbox(item, ctx, acc) do
    ctx = %{
      ctx
      | container: :inbox,
        container_title: item.text,
        project_id: nil,
        project_title: nil,
        task_id: nil,
        inbox: true,
        path: ctx.path ++ [item.text]
    }

    item.notes
    |> skip_notes(acc)
    |> then(&walk(item.children, ctx, &1))
  end

  defp walk_folder(item, ctx, index, acc) do
    acc = count!(acc)
    id = identity(:folder, item, ctx)
    {name, problems} = folder_name(item.text)
    problems = problems ++ folder_problems(item)

    node = %Folder{
      source_id: id,
      name: name,
      parent_source_id: ctx.folder_id,
      dropped: tagged?(item, "dropped"),
      rank: index,
      extras: extra_values(item),
      problems: problems
    }

    child_ctx = %{
      ctx
      | folder_id: id,
        container: :folder,
        container_title: name,
        project_id: nil,
        project_title: nil,
        task_id: nil,
        inbox: false,
        path: ctx.path ++ [item.text]
    }

    acc = %{acc | folders: [node | acc.folders]}

    item.children
    |> positioned()
    |> Enum.reduce(acc, fn {child, child_index, nth}, acc ->
      walk_folder_child(child, %{child_ctx | nth: nth}, child_index, acc)
    end)
  end

  defp walk_project(item, ctx, index, acc) do
    acc = count!(acc)
    id = identity(:project, item, ctx)
    {acc, tag_ids, fields, problems} = read_fields(item, acc)
    problems = if nested?(ctx), do: [nested_problem(ctx) | problems], else: problems

    node = %ProjectNode{
      source_id: id,
      title: blank_title(item.text),
      notes: blank_text(item.notes),
      url: fields.url,
      folder_source_id: ctx.folder_id,
      state: fields.state,
      defer_until: fields.defer_until,
      planned: fields.planned,
      due: fields.due,
      resolved_at: fields.resolved_at,
      recurrence: fields.recurrence,
      deferred_indefinitely: fields.deferred_indefinitely,
      tag_source_ids: tag_ids,
      flagged: fields.flagged,
      rank: index,
      extras: fields.extras,
      problems: problems
    }

    child = %{
      ctx
      | container: :project,
        container_title: node.title,
        project_id: id,
        project_title: node.title,
        task_id: nil,
        inbox: false,
        path: ctx.path ++ [item.text]
    }

    %{acc | projects: [node | acc.projects]}
    |> then(&walk(item.children, child, &1))
  end

  defp walk_task(item, ctx, _index, acc) do
    acc = count!(acc)
    id = identity(:task, item, ctx)
    {acc, tag_ids, fields, problems} = read_fields(item, acc)
    {inbox, project_id, parent_id} = task_place(ctx)

    node = %TaskNode{
      source_id: id,
      title: blank_title(item.text),
      notes: blank_text(item.notes),
      url: fields.url,
      inbox: inbox,
      project_source_id: project_id,
      parent_source_id: parent_id,
      state: fields.state,
      defer_until: fields.defer_until,
      planned: fields.planned,
      due: fields.due,
      resolved_at: fields.resolved_at,
      recurrence: fields.recurrence,
      deferred_indefinitely: fields.deferred_indefinitely,
      tag_source_ids: tag_ids,
      flagged: fields.flagged,
      extras: fields.extras,
      problems: problems
    }

    child = %{
      ctx
      | container: :task,
        container_title: node.title,
        task_id: id,
        inbox: inbox,
        project_id: project_id,
        path: ctx.path ++ [item.text]
    }

    %{acc | tasks: [node | acc.tasks]}
    |> then(&walk(item.children, child, &1))
  end

  # A folder cannot hold a task, so its own tasks come in through the inbox.
  # Projects and nested folders stay in the folder.
  defp walk_folder_child(%{type: :task} = item, ctx, index, acc) do
    ctx = %{
      ctx
      | container: :inbox,
        project_id: nil,
        project_title: nil,
        task_id: nil,
        inbox: true
    }

    walk_task(item, ctx, index, acc)
  end

  defp walk_folder_child(item, ctx, index, acc), do: walk_item(item, ctx, index, acc)

  defp task_place(%{container: :task} = ctx), do: {ctx.inbox, ctx.project_id, ctx.task_id}
  defp task_place(%{inbox: true}), do: {true, nil, nil}
  defp task_place(ctx), do: {false, ctx.project_id, nil}

  defp nested?(%{container: container}) when container in [:project, :task], do: true
  defp nested?(_ctx), do: false

  defp nested_problem(ctx) do
    {:nested_project, "Nested project", ctx.container_title || "Untitled"}
  end

  defp inbox_name?(text) do
    text |> String.normalize(:nfc) |> String.downcase() == "inbox"
  end

  defp folder?(item) do
    tagged?(item, "folder") or
      (Enum.any?(item.children, &(&1.type == :project)) and
         not Enum.any?(item.children, &(&1.type == :task)))
  end

  defp tagged?(item, name) do
    Enum.any?(item.tags, fn {tag, _value} -> String.downcase(tag) == name end)
  end

  defp folder_name(text) do
    name = text |> String.normalize(:nfc) |> String.trim()

    cond do
      name == "" -> {"Untitled", []}
      String.length(name) > 200 -> {String.slice(name, 0, 200), ["name"]}
      true -> {name, []}
    end
  end

  defp folder_problems(item) do
    notes = if item.notes in [nil, ""], do: [], else: ["notes"]
    done = if tagged?(item, "done"), do: ["done"], else: []
    notes ++ done
  end

  # Without `@id`, a line is its kind, the titles above it, its title, and
  # which of its same-titled siblings it is, so a line added elsewhere
  # leaves it the same record. A renamed line is a new one.
  defp identity(kind, item, ctx) do
    case explicit_id(item) do
      nil ->
        material =
          Enum.join(
            [
              Atom.to_string(kind),
              Enum.join(ctx.path, "\n"),
              title_key(item.text),
              Integer.to_string(ctx.nth)
            ],
            "\n"
          )

        "line:" <> Base.encode16(:crypto.hash(:sha256, material), case: :lower)

      id ->
        id
    end
  end

  defp explicit_id(item) do
    case lookup(item.tags, "id") do
      :missing ->
        nil

      value ->
        id = value |> unescape() |> String.trim() |> String.slice(0, 200)
        if id == "", do: nil, else: id
    end
  end

  defp read_fields(item, acc) do
    {acc, tag_ids} = collect_tags(item, acc)
    fields = build_fields(item)
    {acc, tag_ids, fields, fields.problems}
  end

  defp collect_tags(item, acc) do
    bare =
      item.tags
      |> Enum.map(fn {name, _value} -> name end)
      |> Enum.reject(&reserved?/1)
      |> Enum.map(&[&1])

    paths =
      case lookup(item.tags, "tags") do
        :missing -> []
        value -> tag_paths(value)
      end

    {acc, ids} =
      Enum.reduce(bare ++ paths, {acc, []}, fn segments, {acc, ids} ->
        {acc, id} = ensure_path(segments, acc)
        {acc, if(id, do: [id | ids], else: ids)}
      end)

    {acc, ids |> Enum.reverse() |> Enum.uniq()}
  end

  defp tag_paths(value) when value in [nil, ""], do: []

  defp tag_paths(value) do
    value
    |> split_commas()
    |> Enum.map(&unescape/1)
    |> Enum.map(&tag_segments/1)
    |> Enum.reject(&(&1 == []))
  end

  defp tag_segments(piece) do
    piece
    |> String.split(" : ")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp ensure_path(segments, acc) do
    {acc, leaf} =
      Enum.reduce(segments, {acc, nil}, fn name, {acc, parent_id} ->
        case normalize_tag_name(name) do
          nil -> {acc, parent_id}
          name -> ensure_tag(acc, parent_id, name)
        end
      end)

    {acc, leaf}
  end

  defp ensure_tag(acc, parent_id, name) do
    source_id = tag_source_id(parent_id, name)

    case acc.tags[source_id] do
      %TagNode{} ->
        {acc, source_id}

      nil ->
        node = %TagNode{
          source_id: source_id,
          name: name,
          parent_source_id: parent_id,
          state: "active",
          rank: acc.tag_rank
        }

        acc = %{
          acc
          | tags: Map.put(acc.tags, source_id, node),
            tag_list: [node | acc.tag_list],
            tag_rank: acc.tag_rank + 1
        }

        {acc, source_id}
    end
  end

  defp tag_source_id(parent_id, name) do
    "tag:" <> (parent_id || "root") <> ":" <> String.downcase(name)
  end

  defp normalize_tag_name(name) do
    name = name |> String.trim() |> String.normalize(:nfc) |> String.slice(0, @tag_max)
    if name == "", do: nil, else: name
  end

  defp reserved?(name), do: MapSet.member?(@reserved, String.downcase(name))

  defp build_fields(item) do
    tags = item.tags
    {state, resolved_at, state_problems} = state_fields(tags)
    {defer_until, indefinite, defer_problems} = defer_fields(tags)
    {planned, planned_problems} = one_date(tags, "planned", "Planned")
    {due, due_problems} = one_date(tags, "due", "Due")
    {url, url_problems} = url_field(tags)

    problems =
      state_problems ++ defer_problems ++ planned_problems ++ due_problems ++ url_problems

    row = repeat_row(tags, defer_until, planned, due)
    {recurrence, repeat_problems} = repeat_fields(row)

    %{
      state: state,
      resolved_at: resolved_at,
      defer_until: defer_until,
      deferred_indefinitely: indefinite,
      planned: planned,
      due: due,
      url: url,
      flagged: lookup(tags, "flagged") != :missing,
      recurrence: recurrence,
      extras: extra_values(item),
      problems: problems ++ repeat_problems
    }
  end

  defp state_fields(tags) do
    dropped = lookup(tags, "dropped")
    done = lookup(tags, "done")

    cond do
      dropped != :missing -> state_value("dropped", "Dropped", dropped)
      done != :missing -> state_value("done", "Done", done)
      true -> {"to_do", nil, []}
    end
  end

  defp state_value(state, label, value) do
    case normalize_date(value) do
      :empty -> {state, nil, []}
      {:ok, text} -> {state, text, []}
      :error -> {state, nil, [{:unread_value, label, value}]}
    end
  end

  defp defer_fields(tags) do
    chosen =
      case lookup(tags, "defer") do
        :missing -> lookup(tags, "start")
        value -> value
      end

    case chosen do
      :missing ->
        {nil, false, []}

      value ->
        case normalize_date(value) do
          :empty -> {nil, true, []}
          {:ok, text} -> {text, false, []}
          :error -> {nil, false, [{:unread_value, "Defer", value}]}
        end
    end
  end

  defp one_date(tags, name, label) do
    case lookup(tags, name) do
      :missing ->
        {nil, []}

      value ->
        case normalize_date(value) do
          :empty -> {nil, []}
          {:ok, text} -> {text, []}
          :error -> {nil, [{:unread_value, label, value}]}
        end
    end
  end

  defp url_field(tags) do
    case lookup(tags, "url") do
      :missing ->
        {nil, []}

      value ->
        url = value |> unescape() |> String.trim()

        cond do
          url == "" -> {nil, []}
          Url.valid?(url) -> {url, []}
          true -> {nil, [{:unread_value, "URL", url}]}
        end
    end
  end

  defp repeat_row(tags, defer_until, planned, due) do
    %{
      "repeat" => present_value(lookup(tags, "repeat-rule")),
      "repeat_schedule" => present_value(lookup(tags, "repeat-schedule-type")),
      "repeat_anchor" => present_value(lookup(tags, "repeat-anchor-date")),
      "repeat_method" => present_value(lookup(tags, "repeat-method")),
      "repeat_catch_up" => present_value(lookup(tags, "repeat-catch-up")),
      "due" => due,
      "start" => defer_until,
      "planned" => planned
    }
  end

  defp present_value(:missing), do: nil
  defp present_value(nil), do: nil
  defp present_value(value), do: value

  defp repeat_fields(row) do
    case read_repeat(row) do
      {:ok, rule, []} ->
        {rule, []}

      {:ok, rule, changes} ->
        {rule,
         [
           {:approximate_recurrence, "Repeat",
            "#{repeat_text(row)}; imported as a repeat that #{Enum.join(changes, ", and ")}"}
         ]}

      {:undated, anchor} ->
        {nil,
         [
           {:missing_recurrence, "Repeat",
            "#{repeat_text(row)}; no #{@anchor_labels[anchor]} date for the repeat to move"}
         ]}

      :error ->
        if present?(row["repeat"]),
          do: {nil, [{:missing_recurrence, "Repeat", repeat_text(row)}]},
          else: {nil, []}
    end
  end

  defp read_repeat(row) do
    with {:ok, rule, changes} <- OmnifocusRecurrence.read(row),
         true <- Series.valid_rule?(rule) do
      {:ok, rule, changes}
    else
      {:undated, _anchor} = undated -> undated
      _ -> :error
    end
  end

  defp repeat_text(row) do
    details =
      [
        row["repeat_method"] && "method " <> row["repeat_method"],
        row["repeat_schedule"] && "schedule " <> row["repeat_schedule"],
        row["repeat_anchor"] && "based on " <> row["repeat_anchor"],
        row["repeat_catch_up"] == "true" && "catch up automatically"
      ]
      |> Enum.filter(&present?/1)

    if details == [], do: row["repeat"], else: "#{row["repeat"]} (#{Enum.join(details, ", ")})"
  end

  defp extra_values(item) do
    ~w(autodone parallel estimate repeat-rule repeat-method repeat-schedule-type repeat-anchor-date repeat-catch-up)
    |> Enum.reduce(%{}, fn name, extras ->
      case lookup(item.tags, name) do
        :missing -> extras
        value -> Map.put(extras, String.replace(name, "-", "_"), value || "true")
      end
    end)
  end

  defp lookup(tags, name) do
    tags
    |> Enum.filter(fn {tag, _value} -> String.downcase(tag) == name end)
    |> List.last()
    |> case do
      nil -> :missing
      {_tag, value} -> value
    end
  end

  defp normalize_date(:missing), do: :empty
  defp normalize_date(nil), do: :empty

  defp normalize_date(value) do
    value = value |> to_string() |> String.trim() |> unescape()

    cond do
      value == "" -> :empty
      Dates.parse_source(value, :due_at, "Etc/UTC") -> {:ok, value}
      true -> loosen(value)
    end
  end

  defp loosen(value) do
    spaced = space_to_iso(value)

    cond do
      is_binary(spaced) && Dates.parse_source(spaced, :due_at, "Etc/UTC") -> {:ok, spaced}
      clock = clock_time(value) -> {:ok, clock}
      true -> :error
    end
  end

  defp space_to_iso(value) do
    case String.split(value, " ", parts: 2) do
      [date, time] ->
        time = ensure_seconds(time)
        if time, do: date <> "T" <> time

      _ ->
        nil
    end
  end

  defp ensure_seconds(time) do
    cond do
      Regex.match?(~r/\A\d{2}:\d{2}:\d{2}\z/, time) -> time
      Regex.match?(~r/\A\d{2}:\d{2}\z/, time) -> time <> ":00"
      true -> nil
    end
  end

  defp clock_time(value) do
    case Regex.run(
           ~r/\A(\d{4}-\d{2}-\d{2})[ T](\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])\z/,
           value
         ) do
      [_, date, hour, minute, ampm] -> format_clock(date, hour, minute, ampm)
      _ -> nil
    end
  end

  defp format_clock(date, hour, minute, ampm) do
    with {hour, ""} <- Integer.parse(hour),
         minute <- clock_minute(minute),
         h24 when is_integer(h24) <- to_24(hour, String.downcase(ampm)),
         true <- minute in 0..59 do
      :io_lib.format("~sT~2..0B:~2..0B:00", [date, h24, minute]) |> IO.iodata_to_binary()
    else
      _ -> nil
    end
  end

  defp clock_minute(minute) when minute in [nil, ""], do: 0

  defp clock_minute(text) do
    case Integer.parse(text) do
      {minute, ""} -> minute
      _ -> -1
    end
  end

  defp to_24(12, "am"), do: 0
  defp to_24(12, "pm"), do: 12
  defp to_24(hour, "am") when hour in 1..11, do: hour
  defp to_24(hour, "pm") when hour in 1..11, do: hour + 12
  defp to_24(_hour, _ampm), do: nil

  defp split_commas(text), do: split_commas(text, "", [])

  defp split_commas(<<"\\", char::utf8, rest::binary>>, current, acc),
    do: split_commas(rest, current <> "\\" <> <<char::utf8>>, acc)

  defp split_commas(<<",", rest::binary>>, current, acc),
    do: split_commas(rest, "", [current | acc])

  defp split_commas(<<char::utf8, rest::binary>>, current, acc),
    do: split_commas(rest, current <> <<char::utf8>>, acc)

  defp split_commas("", current, acc), do: Enum.reverse([current | acc])

  defp unescape(nil), do: ""
  defp unescape(text), do: unescape(text, "")
  defp unescape(<<"\\\\", rest::binary>>, acc), do: unescape(rest, acc <> "\\")
  defp unescape(<<"\\(", rest::binary>>, acc), do: unescape(rest, acc <> "(")
  defp unescape(<<"\\)", rest::binary>>, acc), do: unescape(rest, acc <> ")")
  defp unescape(<<"\\,", rest::binary>>, acc), do: unescape(rest, acc <> ",")
  defp unescape(<<char::utf8, rest::binary>>, acc), do: unescape(rest, acc <> <<char::utf8>>)
  defp unescape("", acc), do: acc

  defp skip_notes(notes, acc) when notes in [nil, ""], do: acc

  defp skip_notes(notes, acc) do
    extra =
      notes
      |> String.split("\n")
      |> Enum.count(&(String.trim(&1) != ""))

    %{acc | skipped: acc.skipped + extra}
  end

  defp count!(acc) do
    if acc.count >= acc.limits.records do
      raise ArgumentError, "This outline has too many items."
    else
      %{acc | count: acc.count + 1}
    end
  end

  defp blank_title(text) do
    case String.trim(text) do
      "" -> "Untitled"
      title -> title
    end
  end

  defp blank_text(text) when text in [nil, ""], do: nil
  defp blank_text(text), do: text

  defp present?(value), do: is_binary(value) and value != ""

  # Prepend stores newest first. The first copy of a source id is the last
  # one in the file, and that one is the record the import writes.
  defp last_wins(nodes) do
    nodes
    |> Enum.uniq_by(& &1.source_id)
    |> Enum.reverse()
  end

  defp taskpaper_name?(filename) do
    filename |> to_string() |> String.downcase() |> String.ends_with?(".taskpaper")
  end

  defp zip?(<<0x50, 0x4B, 0x03, 0x04, _rest::binary>>), do: true
  defp zip?(_bytes), do: false
end
