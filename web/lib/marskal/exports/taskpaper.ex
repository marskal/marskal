defmodule Marskal.Exports.Taskpaper do
  @moduledoc """
  Writes tasks, projects, and folders as a TaskPaper outline (ADR 0013).

  Inbox is a project named Inbox. A task with no project stays at the top.
  `@id` is the record, so importing the file again updates it.
  """

  import Ecto.Query

  alias Marskal.Accounts
  alias Marskal.Dates
  alias Marskal.Imports.Taskpaper
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects.Project
  alias Marskal.Recurrence.Series
  alias Marskal.Repo
  alias Marskal.Tags.ProjectTag
  alias Marskal.Tags.Tag
  alias Marskal.Tags.TaskTag
  alias Marskal.Tasks.Task

  @freqs %{
    minutes: "MINUTELY",
    hours: "HOURLY",
    days: "DAILY",
    weeks: "WEEKLY",
    months: "MONTHLY",
    years: "YEARLY"
  }

  @days %{
    1 => "MO",
    2 => "TU",
    3 => "WE",
    4 => "TH",
    5 => "FR",
    6 => "SA",
    7 => "SU",
    monday: "MO",
    tuesday: "TU",
    wednesday: "WE",
    thursday: "TH",
    friday: "FR",
    saturday: "SA",
    sunday: "SU"
  }

  def filename(user) do
    day = user |> Accounts.timezone() |> Dates.today() |> Date.to_iso8601()
    "marskal-#{day}.taskpaper"
  end

  def render(user) do
    folders = live(ProjectFolder, user)
    projects = live(Project, user)
    tasks = live(Task, user)
    build(user, folders, projects, tasks)
  end

  defp build(_user, [], [], []), do: ""

  defp build(user, folders, projects, tasks) do
    zone = Accounts.timezone(user)
    folder_ids = MapSet.new(folders, & &1.id)
    project_ids = MapSet.new(projects, & &1.id)
    task_ids = MapSet.new(tasks, & &1.id)
    roots = roots(tasks, task_ids)
    series = load_series(projects, tasks)

    ctx = %{
      zone: zone,
      labels: labels(user),
      series: series,
      latest: latest_ids(tasks ++ projects),
      folders: group_folders(folders, folder_ids),
      projects: group_projects(projects, folder_ids),
      by_project: group_project_tasks(roots, project_ids),
      by_parent: group_children(tasks, task_ids)
    }

    inbox = inbox_items(roots, project_ids, ctx)
    loose = loose_items(roots, project_ids, ctx)
    Taskpaper.dump(inbox ++ loose ++ containers(nil, ctx))
  end

  defp live(schema, user) do
    schema
    |> where([row], row.user_id == ^user.id and is_nil(row.discarded_at))
    |> order_by([row], asc: row.rank, asc: row.id)
    |> Repo.all()
  end

  defp roots(tasks, ids) do
    tasks
    |> Enum.filter(&root?(&1, ids))
    |> Enum.sort_by(&{&1.rank, &1.id})
  end

  defp root?(%{parent_id: nil}, _ids), do: true
  defp root?(%{parent_id: parent_id}, ids), do: parent_id not in ids

  defp group_folders(folders, ids) do
    Enum.group_by(folders, fn folder ->
      if folder.parent_id in ids, do: folder.parent_id
    end)
  end

  defp group_projects(projects, ids) do
    Enum.group_by(projects, fn project ->
      if project.project_folder_id in ids, do: project.project_folder_id
    end)
  end

  defp group_project_tasks(roots, project_ids) do
    roots
    |> Enum.filter(&(&1.project_id in project_ids))
    |> Enum.group_by(& &1.project_id)
  end

  defp group_children(tasks, ids) do
    tasks
    |> Enum.filter(&(&1.parent_id in ids))
    |> Enum.group_by(& &1.parent_id)
    |> Map.new(fn {id, list} -> {id, Enum.sort_by(list, &{&1.rank, &1.id})} end)
  end

  defp inbox_items(roots, project_ids, ctx) do
    tasks =
      Enum.filter(roots, fn task ->
        task.project_id not in project_ids and task.inbox
      end)

    case tasks do
      [] ->
        []

      tasks ->
        [
          %Taskpaper{
            type: :project,
            text: "Inbox",
            notes: "",
            tags: [],
            children: Enum.map(tasks, &task_item(&1, ctx))
          }
        ]
    end
  end

  defp loose_items(roots, project_ids, ctx) do
    roots
    |> Enum.filter(fn task -> task.project_id not in project_ids and not task.inbox end)
    |> Enum.map(&task_item(&1, ctx))
  end

  defp containers(parent_id, ctx) do
    children = Map.get(ctx.folders, parent_id, []) ++ Map.get(ctx.projects, parent_id, [])

    children
    |> Enum.sort_by(&{&1.rank, &1.id})
    |> Enum.map(&container_item(&1, ctx))
  end

  defp container_item(%ProjectFolder{} = folder, ctx) do
    %Taskpaper{
      type: :project,
      text: folder.name,
      notes: "",
      tags: folder_tags(folder),
      children: containers(folder.id, ctx)
    }
  end

  defp container_item(%Project{} = project, ctx) do
    %Taskpaper{
      type: :project,
      text: project.title,
      notes: project.notes || "",
      tags: record_tags(project, ctx),
      children: Enum.map(Map.get(ctx.by_project, project.id, []), &task_item(&1, ctx))
    }
  end

  defp task_item(task, ctx) do
    %Taskpaper{
      type: :task,
      text: task.title,
      notes: task.notes || "",
      tags: record_tags(task, ctx),
      children: Enum.map(Map.get(ctx.by_parent, task.id, []), &task_item(&1, ctx))
    }
  end

  defp folder_tags(folder) do
    dropped = if folder.state == :dropped, do: [{"dropped", nil}], else: []
    [{"folder", nil} | dropped] ++ [{"id", folder.id}]
  end

  defp record_tags(record, ctx) do
    defer_tags(record, ctx.zone) ++
      date_tag(record, :planned_at, "planned", ctx.zone) ++
      date_tag(record, :due_at, "due", ctx.zone) ++
      state_tags(record, ctx.zone) ++
      flag_tag(record) ++
      url_tag(record) ++
      tags_tag(Map.get(ctx.labels, record.id, [])) ++
      repeat_tags(record, ctx) ++
      [{"id", record.id}]
  end

  defp defer_tags(%{deferred_indefinitely: true}, _zone), do: [{"defer", nil}]
  defp defer_tags(record, zone), do: date_tag(record, :defer_until, "defer", zone)

  defp date_tag(record, field, name, zone) do
    case Map.get(record, field) do
      nil -> []
      %DateTime{} = value -> [{name, format_instant(value, field, zone)}]
    end
  end

  defp state_tags(%{state: :to_do}, _zone), do: []

  defp state_tags(%{state: state} = record, zone) do
    value =
      case record.resolved_at do
        nil -> nil
        %DateTime{} = at -> format_instant(at, :resolved_at, zone)
      end

    [{Atom.to_string(state), value}]
  end

  defp flag_tag(%{flagged: true}), do: [{"flagged", nil}]
  defp flag_tag(_record), do: []

  defp url_tag(%{url: url}) when is_binary(url) and url != "", do: [{"url", url}]
  defp url_tag(_record), do: []

  defp tags_tag([]), do: []
  defp tags_tag(labels), do: [{"tags", labels}]

  defp format_instant(datetime, field, zone) do
    {date, time} = Dates.to_local(datetime, zone)

    if time == Dates.default_time(field) do
      Date.to_iso8601(date)
    else
      datetime
      |> DateTime.shift_zone!(zone)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()
    end
  end

  defp labels(user) do
    (tag_rows(TaskTag, :task_id, user) ++ tag_rows(ProjectTag, :project_id, user))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp tag_rows(schema, owner, user) do
    schema
    |> join(:inner, [link], tag in Tag, on: tag.id == link.tag_id)
    |> where(
      [link, tag],
      link.user_id == ^user.id and is_nil(link.discarded_at) and is_nil(tag.discarded_at)
    )
    |> order_by([_link, tag], asc: tag.rank, asc: tag.name, asc: tag.id)
    |> select([link, tag], {field(link, ^owner), tag})
    |> Repo.all()
    |> Enum.map(fn {id, tag} -> {id, Enum.join(tag.parent_path ++ [tag.name], " : ")} end)
  end

  defp load_series(projects, tasks) do
    ids =
      (projects ++ tasks)
      |> Enum.map(& &1.series_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case ids do
      [] ->
        %{}

      ids ->
        Series
        |> where([series], series.id in ^ids and is_nil(series.discarded_at))
        |> Repo.all()
        |> Map.new(&{&1.id, &1})
    end
  end

  defp latest_ids(records) do
    records
    |> Enum.filter(&(&1.series_id && &1.state == :to_do))
    |> Enum.group_by(& &1.series_id)
    |> Map.new(fn {id, rows} ->
      {id, Enum.max_by(rows, &(&1.occurrence_for || ~U[0000-01-01 00:00:00Z])).id}
    end)
  end

  defp repeat_tags(%{series_id: nil}, _ctx), do: []

  defp repeat_tags(record, ctx) do
    series = ctx.series[record.series_id]

    cond do
      is_nil(series) or series.stopped_at -> []
      record.state != :to_do -> []
      ctx.latest[record.series_id] != record.id -> []
      true -> encode_repeat(series)
    end
  end

  # A rule the RRULE cannot say is left out rather than written wrong.
  defp encode_repeat(series) do
    case limit_parts(series) do
      :error ->
        []

      limits ->
        [
          {"repeat-rule", rrule(series, limits)},
          {"repeat-schedule-type", schedule_type(series.mode)},
          {"repeat-anchor-date", anchor_name(series.anchor)}
        ]
    end
  end

  defp schedule_type(:on_completion), do: "from-completion"
  defp schedule_type(_mode), do: "from-assigned"

  defp anchor_name(:defer), do: "dateToStart"
  defp anchor_name(:planned), do: "datePlanned"
  defp anchor_name(:due), do: "dateDue"

  defp rrule(series, limits) do
    ["FREQ=#{@freqs[series.frequency]}"]
    |> interval(series)
    |> Kernel.++(limits)
    |> count_part(series)
    |> until_part(series)
    |> Kernel.++(["WKST=#{@days[series.week_start]}"])
    |> Enum.join(";")
  end

  defp interval(parts, %{interval: interval}) when is_integer(interval) and interval > 1 do
    parts ++ ["INTERVAL=#{interval}"]
  end

  defp interval(parts, _series), do: parts

  defp count_part(parts, %{end_count: count}) when is_integer(count) and count > 0 do
    parts ++ ["COUNT=#{count}"]
  end

  defp count_part(parts, _series), do: parts

  defp until_part(parts, %{ends_at: %DateTime{} = ends_at}) do
    parts ++ ["UNTIL=#{compact_until(ends_at)}"]
  end

  defp until_part(parts, _series), do: parts

  defp compact_until(datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace("-", "")
    |> String.replace(":", "")
  end

  defp limit_parts(%{frequency: :weeks, weekdays: days}) when days != [] do
    ["BYDAY=#{days |> Enum.sort() |> Enum.map_join(",", &@days[&1])}"]
  end

  defp limit_parts(%{frequency: :months, on_days: days}) when days != [] do
    day_parts(Series.day_rules(%Series{on_days: days}))
  end

  defp limit_parts(%{frequency: :years, on_days: days}) when days != [] do
    yearly_parts(Series.day_rules(%Series{on_days: days}))
  end

  defp limit_parts(_series), do: []

  defp yearly_parts(rules) do
    grouped = Enum.group_by(rules, &elem(&1, 0))
    sets = grouped |> Map.values() |> Enum.map(&day_signature/1) |> Enum.uniq()
    months = grouped |> Map.keys() |> Enum.reject(&is_nil/1) |> Enum.sort()

    with {[_], [_ | _]} <- {sets, months},
         [_ | _] = days <- day_parts(rules) do
      ["BYMONTH=#{Enum.join(months, ",")}" | days]
    else
      _ -> :error
    end
  end

  # Yearly rows carry a month. The day parts are the month's rows, once.
  defp day_signature(rules) do
    rules
    |> Enum.map(fn {_month, ordinal, kind} -> {ordinal, kind} end)
    |> Enum.sort()
  end

  # The rows are one set of days, but RRULE parts narrow each other, so
  # only one kind of row can be said: calendar days, nth weekdays, or nth
  # work days or weekend days.
  defp day_parts(rules) do
    calendar = for {_month, ordinal, :day} <- rules, uniq: true, do: ordinal

    weekdays =
      for {_month, ordinal, kind} <- rules, code = @days[kind], uniq: true, do: {ordinal, code}

    specials =
      for {_month, ordinal, kind} <- rules, kind in [:work_day, :weekend_day], do: {kind, ordinal}

    case {calendar, weekdays, specials} do
      {[_ | _], [], []} -> ["BYMONTHDAY=#{calendar |> Enum.sort() |> Enum.join(",")}"]
      {[], [_ | _], []} -> weekday_part(weekdays)
      {[], [], [_ | _]} -> setpos_part(specials)
      _ -> :error
    end
  end

  defp weekday_part(weekdays) do
    codes = Enum.map_join(weekdays, ",", fn {ordinal, code} -> "#{ordinal}#{code}" end)
    ["BYDAY=#{codes}"]
  end

  defp setpos_part(specials) do
    case Enum.uniq(Enum.map(specials, &elem(&1, 0))) do
      [kind] ->
        days = if kind == :work_day, do: "MO,TU,WE,TH,FR", else: "SA,SU"
        positions = specials |> Enum.map(&Integer.to_string(elem(&1, 1))) |> Enum.uniq()
        ["BYDAY=#{days}", "BYSETPOS=#{Enum.join(positions, ",")}"]

      _kinds ->
        :error
    end
  end
end
