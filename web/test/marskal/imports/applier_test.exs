defmodule Marskal.Imports.ApplierTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Changes.Change
  alias Marskal.ImportBatch
  alias Marskal.ImportItem
  alias Marskal.Imports
  alias Marskal.Imports.Applier
  alias Marskal.Imports.Parser
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects.Project
  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series
  alias Marskal.Tags
  alias Marskal.Tags.Tag
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  test "creates folders projects and tasks for the user", %{user: user} do
    batch = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert batch.status == :previewed

    assert {:ok, batch} = Applier.call(batch)
    assert batch.status == :applied

    work = folder!(batch, "folderWork00")
    assert work.name == "Work"
    dropped = folder!(batch, "folderOld000")
    assert dropped.state == :dropped

    project = project!(batch, "projSite0000")
    assert project.title == "Launch website"
    assert project.project_folder_id == work.id
    assert project.state == :to_do
    assert project.notes == "Public site"

    draft = task!(batch, "taskDraft000")
    refute draft.inbox
    assert draft.project_id == project.id
    assert draft.state == :to_do
    assert draft.due_at == ~U[2024-03-01 16:00:00Z]
    assert draft.defer_until == ~U[2024-02-20 08:00:00Z]
    assert draft.planned_at == nil

    milk = task!(batch, "taskInbox000")
    assert milk.inbox
    assert milk.project_id == nil

    both = task!(batch, "taskBoth0000")
    refute both.inbox
    assert both.project_id == project.id

    done = task!(batch, "taskDone0000")
    assert done.state == :done
    assert done.resolved_at == ~U[2024-02-01 00:00:00Z]
  end

  test "second import skips existing source ids", %{user: user} do
    batch = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert {:ok, _} = Applier.call(batch)
    created = task_items(user)

    batch2 = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert {:ok, batch2} = Applier.call(batch2)

    assert task_items(user) == created
    assert batch2.stats["created"]["tasks"] == 0
    assert batch2.stats["skipped"]["tasks"] > 0
  end

  test "a re-import leaves notes the user has edited", %{user: user} do
    batch = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert {:ok, batch} = Applier.call(batch)
    project = project!(batch, "projSite0000")

    {:ok, _} =
      Marskal.Projects.set_notes(user, project.id, "My notes", Ecto.UUID.generate(version: 7))

    batch2 = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert {:ok, _} = Applier.call(batch2)

    assert Repo.get!(Project, project.id).notes == "My notes"
  end

  test "each record is one change, and the payload is dropped after apply", %{user: user} do
    batch = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert {:ok, batch} = Applier.call(batch)

    done = task!(batch, "taskDone0000")
    assert Repo.aggregate(from(c in Change, where: c.entity_id == ^done.id), :count) == 1

    assert Repo.one!(from b in ImportBatch, where: b.id == ^batch.id, select: b.payload) == nil
    assert [%ImportBatch{payload: nil}] = Marskal.Imports.list_batches(user)
  end

  test "the list of batches does not load payloads", %{user: user} do
    batch = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert [%ImportBatch{payload: nil}] = Marskal.Imports.list_batches(user)
    assert Marskal.Imports.load_payload(Marskal.Imports.get_batch(user, batch.id)).payload
    assert Marskal.Imports.get_batch(user, "not-a-uuid") == nil
  end

  test "applies an OmniFocus 4.9 tutorial backup", %{user: user} do
    batch =
      preview!(user, OmnifocusBackup.tutorial_backup(), "omnifocus-tutorial.ofocus-backup.zip")

    assert batch.status == :previewed
    assert batch.stats["projects"] == 2
    assert batch.stats["tasks"] >= 20

    assert {:ok, applied} = Applier.call(batch)
    assert applied.status == :applied

    tutorial = Repo.get_by!(Project, user_id: user.id, title: "Get to know OmniFocus 4 for Mac")
    titles = user |> Tasks.list_project_tasks(tutorial.id) |> Enum.map(& &1.title)
    assert "Click this action" in titles

    brokka = Repo.get_by!(Project, user_id: user.id, title: "Brokkassen")

    brokka_titles =
      user |> Tasks.list_project_tasks(brokka.id) |> Enum.map(& &1.title) |> Enum.sort()

    assert brokka_titles == ["Gør noget", "Gør noget andet"]

    done = Repo.get_by!(Task, user_id: user.id, title: "Create a project")
    assert done.state == :done

    inspector = Repo.get_by!(Task, user_id: user.id, title: "Check out the Inspector")
    assert inspector.notes =~ "Click the Inspect button"
    refute inspector.notes =~ "AppleSystemUIFont"
  end

  describe "tags" do
    test "creates the tree in source order, with states and links", %{user: user} do
      {:ok, batch} =
        user |> preview!(OmnifocusBackup.tagged_backup(), "tagged.zip") |> Applier.call()

      assert batch.stats["created"]["tags"] == 5
      assert batch.stats["skipped"]["tags"] == 1

      tree = Tags.tree(user)

      assert tree |> Tags.Tree.children(nil) |> Enum.map(& &1.name) ==
               ~w(Waiting Person Home Old)

      assert Tags.Tree.get(tree, tag!(batch, "ctxWife0000").id).parent_path == ["Person"]
      assert tag!(batch, "ctxWait0000").state == :on_hold
      assert tag!(batch, "ctxOld00000").state == :dropped

      call = task!(batch, "taskCall000")
      garden = project!(batch, "projGarden0")
      effective = Tags.effective_tags(user, [call], tree)[call.id]

      assert Enum.map(effective, &{&1.tag.name, &1.inherited}) == [
               {"Waiting", false},
               {"Wife", false},
               {"Home", true}
             ]

      assert Tags.project_tags(user, garden, tree) |> Enum.map(& &1.name) == ["Home"]
    end

    test "a tag named like its sibling, ignoring case, is the same tag", %{user: user} do
      {:ok, batch} =
        user |> preview!(OmnifocusBackup.tagged_backup(), "tagged.zip") |> Applier.call()

      assert tag!(batch, "ctxHome2000").id == tag!(batch, "ctxHome1000").id
      fix = task!(batch, "taskFix0000")
      assert [%{tag: %{name: "Home"}}] = Tags.effective_tags(user, [fix], Tags.tree(user))[fix.id]
    end

    test "reuses a tag the user already has at the same place", %{user: user} do
      {:ok, waiting} =
        Tags.create_tag(user, %{"name" => "waiting"}, Ecto.UUID.generate(version: 7))

      {:ok, batch} =
        user |> preview!(OmnifocusBackup.tagged_backup(), "tagged.zip") |> Applier.call()

      assert tag!(batch, "ctxWait0000").id == waiting.id
      assert Tags.get_tag(user, waiting.id).state == :active
    end

    test "a re-import skips tags and leaves the user's tags on tasks alone", %{user: user} do
      {:ok, first} =
        user |> preview!(OmnifocusBackup.tagged_backup(), "tagged.zip") |> Applier.call()

      call = task!(first, "taskCall000")
      wait = tag!(first, "ctxWait0000")
      {:ok, _} = Tags.untag_task(user, call.id, wait.id, Ecto.UUID.generate(version: 7))

      {:ok, second} =
        user |> preview!(OmnifocusBackup.tagged_backup(), "tagged.zip") |> Applier.call()

      assert second.stats["created"]["tags"] == 0
      assert Enum.count(Tags.list_tags(user)) == 5

      names =
        Tags.effective_tags(user, [call], Tags.tree(user))[call.id] |> Enum.map(& &1.tag.name)

      refute "Waiting" in names
    end

    test "the tutorial backup's tags arrive", %{user: user} do
      {:ok, batch} =
        user
        |> preview!(OmnifocusBackup.tutorial_backup(), "omnifocus-tutorial.ofocus-backup.zip")
        |> Applier.call()

      assert batch.stats["created"]["tags"] == 12
      tree = Tags.tree(user)
      paths = tree |> Tags.Tree.all() |> Enum.map(&Tag.path/1)
      assert ["Errands", "Supermarket"] in paths

      assign = Repo.get_by!(Task, user_id: user.id, title: "Assign a tag")

      assert [%{tag: %{name: "Hardware Store"}}] =
               Tags.effective_tags(user, [assign], tree)[assign.id]
    end
  end

  test "applies a todoist snapshot, including labels, and skips it the second time", %{
    user: user
  } do
    {:ok, existing} = Tags.create_tag(user, %{"name" => "Food"}, Ecto.UUID.generate(version: 7))

    batch = preview_todoist!(user)
    assert batch.status == :previewed
    assert batch.stats["tags"] == 5
    assert batch.external_account == "ada@marskal.example"

    assert {:ok, applied} = Applier.call(batch)
    assert applied.stats["created"]["tasks"] == 4
    assert applied.stats["created"]["tags"] == 4
    assert applied.stats["skipped"]["tags"] == 1
    assert Imports.load_payload(applied).payload == nil

    milk = Repo.get_by!(Task, user_id: user.id, title: "Buy milk")
    assert milk.inbox
    tree = Tags.tree(user)

    labels =
      user |> Tags.effective_tags([milk], tree) |> Map.fetch!(milk.id) |> Enum.map(& &1.tag.name)

    assert Enum.sort(labels) == ["Errand", "Food", "Missing repeat rule"]

    food = Repo.get_by!(ImportItem, user_id: user.id, source: "todoist", source_id: "tag:l1")
    assert food.tag_id == existing.id

    editor = Repo.get_by!(Task, user_id: user.id, title: "Ask editor")
    assert editor.url == "https://chat.example/editor"

    # Days with no time take the default time in the user's zone (CEST here).
    assert milk.planned_at == ~U[2026-09-28 07:00:00Z]
    assert milk.due_at == ~U[2026-10-01 15:00:00Z]

    names =
      Tag |> where([t], t.user_id == ^user.id) |> Repo.all() |> Enum.map(& &1.name) |> Enum.sort()

    assert names == [
             "Errand",
             "Food",
             "Import problems",
             "Missing repeat rule",
             "Missing section"
           ]

    again = preview_todoist!(user)
    assert {:ok, again} = Applier.call(again)
    assert again.stats["created"]["tasks"] == 0
    assert again.stats["skipped"]["tasks"] == 4
    assert again.stats["created"]["tags"] == 0

    assert Repo.aggregate(
             from(t in Task, where: t.user_id == ^user.id and t.title == "Buy milk"),
             :count
           ) ==
             1
  end

  describe "repeats" do
    @repeats_xml """
    <?xml version="1.0" encoding="UTF-8"?>
    <omnifocus>
      <task id="projReview0">
        <project><status>active</status></project>
        <name>Monthly review</name>
        <due>2026-10-30T16:00:00.000Z</due>
        <repetition-rule>FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1</repetition-rule>
        <repetition-schedule-type>regularly</repetition-schedule-type>
        <repetition-anchor-date>due-date</repetition-anchor-date>
        <catch-up-automatically>true</catch-up-automatically>
      </task>
      <task id="taskTrash00">
        <inbox/>
        <name>Take out the trash</name>
        <due>2026-10-09T15:00:00.000Z</due>
        <repetition-rule>FREQ=WEEKLY;BYDAY=FR</repetition-rule>
        <repetition-schedule-type>regularly</repetition-schedule-type>
        <repetition-anchor-date>due-date</repetition-anchor-date>
        <catch-up-automatically>true</catch-up-automatically>
      </task>
      <task id="taskPlants0">
        <inbox/>
        <name>Water the plants</name>
        <start>2026-10-09T06:00:00.000Z</start>
        <repetition-rule>FREQ=WEEKLY;BYDAY=TU</repetition-rule>
        <repetition-schedule-type>from-completion</repetition-schedule-type>
        <repetition-anchor-date>defer-date</repetition-anchor-date>
      </task>
      <task id="taskHour000">
        <inbox/>
        <name>Stand up</name>
        <due>2026-10-09T15:00:00.000Z</due>
        <repetition-rule>FREQ=DAILY;BYHOUR=9</repetition-rule>
        <repetition-schedule-type>regularly</repetition-schedule-type>
        <repetition-anchor-date>due-date</repetition-anchor-date>
      </task>
    </omnifocus>
    """

    test "a repeat Marskal can carry makes a series; one it can only come close to is marked",
         %{user: user} do
      batch = preview!(user, OmnifocusBackup.zip_with_xml(@repeats_xml), "x.ofocus-backup")
      assert {:ok, batch} = Applier.call(batch)

      trash = task!(batch, "taskTrash00")
      assert trash.occurrence_for == trash.due_at

      assert %Series{kind: :task, mode: :regular, anchor: :due, frequency: :weeks, weekdays: [5]} =
               Recurrence.get_series(user, trash.series_id)

      assert tag_names(trash) == []

      review = project!(batch, "projReview0")

      assert %Series{kind: :project, frequency: :months, on_days: ["-1:work_day"]} =
               Recurrence.get_series(user, review.series_id)

      plants = task!(batch, "taskPlants0")

      assert %Series{mode: :on_completion, anchor: :defer, frequency: :weeks, weekdays: []} =
               Recurrence.get_series(user, plants.series_id)

      assert tag_names(plants) == ["Approximate repeat rule"]
      assert plants.notes =~ "FREQ=WEEKLY;BYDAY=TU"
      assert plants.notes =~ "without its days"

      hour = task!(batch, "taskHour000")
      assert hour.series_id == nil
      assert tag_names(hour) == ["Missing repeat rule"]
    end
  end

  test "does not import into another user", %{user: user, other: other} do
    batch = preview!(user, OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
    assert {:ok, _} = Applier.call(batch)

    refute Repo.get_by(Task, user_id: other.id, title: "Buy milk")
    refute Repo.get_by(Project, user_id: other.id, title: "Launch website")
  end

  defp preview!(user, bytes, filename) do
    {:ok, batch} =
      %ImportBatch{}
      |> ImportBatch.changeset(%{
        user_id: user.id,
        source: "omnifocus",
        channel: :file,
        status: :pending,
        filename: filename,
        payload: bytes
      })
      |> Repo.insert()

    Parser.call(batch)
  end

  defp preview_todoist!(user) do
    {:ok, batch} =
      %ImportBatch{}
      |> ImportBatch.changeset(%{
        user_id: user.id,
        source: "todoist",
        channel: :oauth,
        status: :pending,
        filename: "Todoist",
        external_account: "ada@marskal.example",
        payload: TodoistSnapshot.json()
      })
      |> Repo.insert()

    Parser.call(batch)
  end

  defp tag_names(task_or_project) do
    {schema, field} =
      case task_or_project do
        %Task{} -> {Tags.TaskTag, :task_id}
        %Project{} -> {Tags.ProjectTag, :project_id}
      end

    Repo.all(
      from l in schema,
        join: t in Tag,
        on: t.id == l.tag_id,
        where: field(l, ^field) == ^task_or_project.id and is_nil(l.discarded_at),
        order_by: t.name,
        select: t.name
    )
  end

  defp folder!(batch, source_id) do
    item = item!(batch, source_id)
    Repo.get!(ProjectFolder, item.project_folder_id)
  end

  defp project!(batch, source_id) do
    item = item!(batch, source_id)
    Repo.get!(Project, item.project_id)
  end

  defp tag!(batch, source_id) do
    %ImportItem{tag_id: id} = item!(batch, source_id)
    Repo.get!(Tag, id)
  end

  defp task!(batch, source_id) do
    item = item!(batch, source_id)
    Repo.get!(Task, item.task_id)
  end

  defp item!(batch, source_id) do
    Repo.get_by!(ImportItem, import_batch_id: batch.id, source_id: source_id)
  end

  defp task_items(user) do
    Repo.aggregate(
      from(i in ImportItem, where: i.user_id == ^user.id and i.kind == :task),
      :count
    )
  end
end
