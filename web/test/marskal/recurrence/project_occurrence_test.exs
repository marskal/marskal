defmodule Marskal.Recurrence.ProjectOccurrenceTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Dates
  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Projects.Project
  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series
  alias Marskal.Tags
  alias Marskal.Tags.ProjectTag
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  @zone "Europe/Copenhagen"
  @friday ~U[2026-10-16 15:00:00Z]

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  test "Done creates the next project, its tasks copied To-Do", %{user: user} do
    {:ok, folder} = ProjectFolders.create_folder(user, %{name: "Home"}, command())
    {:ok, tag} = Tags.create_tag(user, %{name: "weekly"}, command())
    due = hours_ago(1)

    {:ok, project} =
      Projects.create_project(
        user,
        %{
          title: "Review",
          notes: "Inbox zero",
          url: "https://example.com/review",
          flagged: true,
          project_folder_id: folder.id,
          due_at: due
        },
        command()
      )

    {:ok, _} = Tags.tag_project(user, project.id, tag.id, command())

    {:ok, inbox} =
      Tasks.create_task(
        user,
        %{title: "Clear inbox", project_id: project.id, due_at: DateTime.add(due, -1, :day)},
        command()
      )

    {:ok, mail} = Tasks.create_task(user, %{title: "Mail", parent_id: inbox.id}, command())
    {:ok, plan} = Tasks.create_task(user, %{title: "Plan", project_id: project.id}, command())
    {:ok, gone} = Tasks.create_task(user, %{title: "Gone", project_id: project.id}, command())
    {:ok, _} = Tasks.complete_task(user, mail.id, command())
    {:ok, _} = Tasks.drop_task(user, plan.id, command())
    {:ok, _} = Tasks.delete_task(user, gone.id, command())

    rule = %{mode: :on_completion, anchor: :due, interval: 7, frequency: :days}
    {:ok, series} = Recurrence.repeat_project(user, project.id, rule, command())
    {:ok, done} = Projects.complete_project(user, project.id, command())

    [next] = later_occurrences(series, project)
    slot = DateTime.add(done.resolved_at, 7, :day)
    assert next.id == Recurrence.occurrence_id(series.id, slot)

    assert %Project{
             title: "Review",
             notes: "Inbox zero",
             url: "https://example.com/review",
             flagged: true,
             state: :to_do,
             due_at: ^slot,
             occurrence_for: ^slot
           } = next

    assert next.project_folder_id == folder.id
    assert project_tag_ids(next) == [tag.id]

    inbox_id = Marskal.Uuid.v5(next.id, inbox.id)
    mail_id = Marskal.Uuid.v5(next.id, mail.id)

    assert [
             %Task{id: ^inbox_id, title: "Clear inbox", state: :to_do} = inbox_copy,
             %Task{title: "Plan", state: :to_do, inbox: false}
           ] = top_tasks(next)

    assert [%Task{id: ^mail_id, state: :to_do}] = Tasks.Outline.children(inbox_copy)

    {next_day, _} = Dates.to_local(next.due_at, @zone)
    {copy_day, _} = Dates.to_local(inbox_copy.due_at, @zone)
    assert Date.diff(next_day, copy_day) == 1

    # The old project keeps its tasks.
    assert [%Task{id: old_id}, _] = top_tasks(project)
    assert old_id == inbox.id
  end

  test "Dropped skips to the next slot in regular mode", %{user: user} do
    {:ok, project} = Projects.create_project(user, %{title: "Review", due_at: @friday}, command())
    rule = %{mode: :regular, anchor: :due, interval: 1, frequency: :weeks}
    {:ok, series} = Recurrence.repeat_project(user, project.id, rule, command())

    {:ok, _} = Projects.drop_project(user, project.id, command())

    assert [%Project{state: :to_do, occurrence_for: slot}] = later_occurrences(series, project)
    assert DateTime.compare(slot, DateTime.utc_now()) == :gt
  end

  test "a deleted folder is not copied", %{user: user} do
    {:ok, folder} = ProjectFolders.create_folder(user, %{name: "Old"}, command())

    {:ok, project} =
      Projects.create_project(
        user,
        %{title: "Review", due_at: hours_ago(1), project_folder_id: folder.id},
        command()
      )

    rule = %{mode: :on_completion, anchor: :due, interval: 1, frequency: :days}
    {:ok, series} = Recurrence.repeat_project(user, project.id, rule, command())
    {:ok, _} = ProjectFolders.delete_folder(user, folder.id, command())
    {:ok, _} = Projects.complete_project(user, project.id, command())

    assert [%Project{project_folder_id: nil}] = later_occurrences(series, project)
  end

  test "deleting the latest project ends the series", %{user: user} do
    {:ok, project} = Projects.create_project(user, %{title: "Review", due_at: @friday}, command())
    rule = %{mode: :regular, anchor: :due, interval: 1, frequency: :weeks}
    {:ok, series} = Recurrence.repeat_project(user, project.id, rule, command())

    {:ok, _} = Projects.delete_project(user, project.id, command())

    assert %Series{discarded_at: %DateTime{}} = Repo.get!(Series, series.id)
  end

  defp later_occurrences(series, first) do
    Repo.all(
      from p in Project,
        where: p.series_id == ^series.id and p.id != ^first.id and is_nil(p.discarded_at),
        order_by: p.inserted_at
    )
  end

  defp top_tasks(project) do
    Repo.all(
      from t in Task,
        where: t.project_id == ^project.id and is_nil(t.parent_id) and is_nil(t.discarded_at),
        order_by: [asc: t.rank, asc: t.id]
    )
  end

  defp project_tag_ids(project) do
    Repo.all(
      from l in ProjectTag,
        where: l.project_id == ^project.id and is_nil(l.discarded_at),
        select: l.tag_id
    )
  end

  defp hours_ago(hours), do: DateTime.add(DateTime.utc_now(:second), -hours, :hour)
  defp command, do: Ecto.UUID.generate()
end
