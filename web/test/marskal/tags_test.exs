defmodule Marskal.TagsTest do
  use Marskal.DataCase, async: true

  import Ecto.Query
  alias Marskal.AccountsFixtures
  alias Marskal.Changes.Change
  alias Marskal.Projects
  alias Marskal.Repo
  alias Marskal.Tags
  alias Marskal.Tags.Link
  alias Marskal.Tags.ProjectTag
  alias Marskal.Tags.Tag
  alias Marskal.Tags.TaskTag
  alias Marskal.Tasks

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  describe "the tag tree" do
    test "a nested tag remembers its ancestors, through a rename", %{user: user} do
      person = tag!(user, "Person")
      family = tag!(user, "Family", person)
      wife = tag!(user, "Wife", family)

      assert Tag.path(wife) == ["Person", "Family", "Wife"]

      {:ok, _} = Tags.rename_tag(user, person.id, "People", command())
      assert Tag.path(Tags.get_tag(user, wife.id)) == ["People", "Family", "Wife"]
    end

    test "new siblings go last, in byte order", %{user: user} do
      names = ~w(Waiting Someday Errands)
      for name <- names, do: tag!(user, name)
      assert Enum.map(Tags.list_tags(user), & &1.name) == names

      # rank is COLLATE "C": "Z" < "a" < "b". A linguistic collation would
      # put "Z" last.
      for {tag, rank} <- Enum.zip(Tags.list_tags(user), ~w(a Z b)) do
        Repo.update_all(from(t in Tag, where: t.id == ^tag.id), set: [rank: rank])
      end

      assert Enum.map(Tags.list_tags(user), & &1.name) == ~w(Someday Waiting Errands)
    end

    test "a tag cannot move under its own descendant", %{user: user} do
      person = tag!(user, "Person")
      wife = tag!(user, "Wife", person)

      assert {:error, changeset} = Tags.move_tag(user, person.id, wife.id, command())
      assert "would create a cycle" in errors_on(changeset).parent_id
    end

    test "a moved tag takes the last place among its new siblings", %{user: user} do
      person = tag!(user, "Person")
      tag!(user, "Wife", person)
      kid = tag!(user, "Kid")

      {:ok, kid} = Tags.move_tag(user, kid.id, person.id, command())
      assert kid.parent_path == ["Person"]

      assert Tags.list_tags(user)
             |> Enum.filter(&(&1.parent_id == person.id))
             |> Enum.map(& &1.name) ==
               ~w(Wife Kid)
    end

    test "a parent must be one of the user's live tags", %{user: user, other: other} do
      theirs = tag!(other, "Theirs")

      assert {:error, changeset} =
               Tags.create_tag(user, %{"name" => "Mine", "parent_id" => theirs.id}, command())

      assert "must belong to you" in errors_on(changeset).parent_id
    end
  end

  describe "names" do
    test "are unique per parent, ignoring case", %{user: user} do
      tag!(user, "Waiting")

      assert {:error, changeset} = Tags.create_tag(user, %{"name" => "waiting"}, command())
      assert "is already used here" in errors_on(changeset).name
    end

    test "may repeat under another parent", %{user: user} do
      home = tag!(user, "Home")
      work = tag!(user, "Work")

      assert %Tag{} = tag!(user, "Errands", home)
      assert %Tag{} = tag!(user, "Errands", work)
    end

    test "are trimmed and compared in NFC", %{user: user} do
      composed = tag!(user, "  Café  ")
      assert composed.name == "Café"

      # "e" followed by a combining acute accent.
      decomposed = "Cafe" <> <<0x0301::utf8>>
      assert {:error, changeset} = Tags.create_tag(user, %{"name" => decomposed}, command())
      assert "is already used here" in errors_on(changeset).name
    end

    test "may hold separators and emoji", %{user: user} do
      assert tag!(user, "Someday/maybe").name == "Someday/maybe"
      assert tag!(user, "Re: ☕").name == "Re: ☕"
    end

    test "free up once a tag is deleted", %{user: user} do
      waiting = tag!(user, "Waiting")
      {:ok, _} = Tags.delete_tag(user, waiting.id, command())

      assert %Tag{} = tag!(user, "Waiting")
    end
  end

  describe "links" do
    test "tagging twice is one row, and untag then re-tag reuses it", %{user: user} do
      task = task!(user)
      waiting = tag!(user, "Waiting")
      id = Link.id(:task, task.id, waiting.id)

      {:ok, %TaskTag{id: ^id, discarded_at: nil}} =
        Tags.tag_task(user, task.id, waiting.id, command())

      {:ok, %TaskTag{id: ^id}} = Tags.tag_task(user, task.id, waiting.id, command())
      assert changes(user, id) == 1

      {:ok, %TaskTag{id: ^id} = untagged} = Tags.untag_task(user, task.id, waiting.id, command())
      assert untagged.discarded_at

      {:ok, %TaskTag{id: ^id, discarded_at: nil}} =
        Tags.tag_task(user, task.id, waiting.id, command())

      assert changes(user, id) == 3
      assert Repo.aggregate(TaskTag, :count) == 1
    end

    test "projects are tagged the same way", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{"title" => "Garden"}, command())
      home = tag!(user, "Home")

      {:ok, link} = Tags.tag_project(user, project.id, home.id, command())
      assert link.id == Link.id(:project, project.id, home.id)
      assert %ProjectTag{project_id: project_id} = Repo.get!(ProjectTag, link.id)
      assert project_id == project.id
    end

    test "stay inside one user", %{user: user, other: other} do
      task = task!(user)
      mine = tag!(user, "Mine")
      theirs = tag!(other, "Theirs")

      assert {:error, :not_found} = Tags.tag_task(user, task.id, theirs.id, command())
      assert {:error, :not_found} = Tags.tag_task(other, task.id, mine.id, command())
    end
  end

  describe "deleting" do
    test "discards the subtree and its links, and replays as a no-op", %{user: user} do
      task = task!(user)
      person = tag!(user, "Person")
      wife = tag!(user, "Wife", person)
      {:ok, link} = Tags.tag_task(user, task.id, wife.id, command())

      delete = command()
      before = Repo.aggregate(Change, :count)
      {:ok, _} = Tags.delete_tag(user, person.id, delete)

      assert Tags.get_tag(user, person.id) == nil
      assert Tags.get_tag(user, wife.id) == nil
      assert Repo.get!(TaskTag, link.id).discarded_at
      assert Repo.aggregate(Change, :count) == before + 3

      {:ok, _} = Tags.delete_tag(user, person.id, delete)
      assert Repo.aggregate(Change, :count) == before + 3
    end
  end

  describe "merging" do
    test "moves links and children, merging clashing children", %{user: user} do
      [t1, t2, t3] = for _ <- 1..3, do: task!(user)

      target = tag!(user, "Waiting")
      target_home = tag!(user, "home", target)
      duplicate = tag!(user, "Waiting on")
      dup_home = tag!(user, "Home", duplicate)
      dup_car = tag!(user, "Car", duplicate)

      {:ok, _} = Tags.tag_task(user, t1.id, duplicate.id, command())
      {:ok, _} = Tags.tag_task(user, t2.id, dup_home.id, command())
      {:ok, _} = Tags.tag_task(user, t3.id, target.id, command())
      {:ok, _} = Tags.tag_task(user, t3.id, duplicate.id, command())

      {:ok, merged} = Tags.merge_tag(user, duplicate.id, target.id, command())
      assert merged.discarded_at
      assert merged.merged_into_id == target.id

      assert live_tag_ids(t1) == [target.id]
      assert live_tag_ids(t2) == [target_home.id]
      assert live_tag_ids(t3) == [target.id]

      assert Repo.get!(Tag, dup_home.id).merged_into_id == target_home.id
      assert Tag.path(Tags.get_tag(user, dup_car.id)) == ["Waiting", "Car"]
    end

    test "a merged tag stands for the one it went into", %{user: user} do
      task = task!(user)
      target = tag!(user, "Waiting")
      duplicate = tag!(user, "Waiting on")
      {:ok, _} = Tags.merge_tag(user, duplicate.id, target.id, command())

      {:ok, link} = Tags.tag_task(user, task.id, duplicate.id, command())
      assert link.tag_id == target.id
    end

    test "cannot go into its own descendant", %{user: user} do
      person = tag!(user, "Person")
      wife = tag!(user, "Wife", person)

      assert {:error, :into_descendant} = Tags.merge_tag(user, person.id, wife.id, command())
    end
  end

  describe "reading" do
    test "effective tags are the task's own, then its project's", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{"title" => "Garden"}, command())
      task = task!(user, project_id: project.id)
      home = tag!(user, "Home")
      waiting = tag!(user, "Waiting")
      {:ok, _} = Tags.tag_project(user, project.id, home.id, command())
      {:ok, _} = Tags.tag_project(user, project.id, waiting.id, command())
      {:ok, _} = Tags.tag_task(user, task.id, waiting.id, command())

      tree = Tags.tree(user)
      entries = Tags.effective_tags(user, [task], tree)[task.id]

      assert Enum.map(entries, &{&1.tag.name, &1.inherited}) == [
               {"Home", true},
               {"Waiting", false}
             ]
    end

    test "the open stream leaves out tasks blocked by tag state", %{user: user} do
      waiting = tag!(user, "Waiting")
      old = tag!(user, "Old")
      home = tag!(user, "Home")
      held = task!(user, tags: [waiting, home])
      only_dropped = task!(user, tags: [old])
      partly_dropped = task!(user, tags: [old, home])
      plain = task!(user)

      {:ok, _} = Tags.set_tag_state(user, waiting.id, :on_hold, command())
      {:ok, _} = Tags.set_tag_state(user, old.id, :dropped, command())

      assert ids(Tasks.list_open(user)) == Enum.sort([partly_dropped.id, plain.id])

      assert ids(Tasks.list_open(user, unavailable: true)) ==
               Enum.sort([held.id, only_dropped.id, partly_dropped.id, plain.id])
    end

    test "a tag's outline groups tasks by child tag", %{user: user} do
      person = tag!(user, "Person")
      family = tag!(user, "Family", person)
      wife = tag!(user, "Wife", family)
      kid = tag!(user, "Kid", person)
      old = tag!(user, "Old", person)
      {:ok, _} = Tags.set_tag_state(user, old.id, :dropped, command())

      {:ok, project} = Projects.create_project(user, %{"title" => "Anniversary"}, command())
      {:ok, _} = Tags.tag_project(user, project.id, wife.id, command())

      direct = task!(user, tags: [person])
      both = task!(user, tags: [person, wife])
      via_project = task!(user, project_id: project.id)
      in_inbox = task!(user, inbox: true, tags: [wife])
      done = task!(user, tags: [person])
      {:ok, _} = Tasks.complete_task(user, done.id, command())
      _hidden = task!(user, tags: [old])

      %{root: root, unavailable: unavailable} = Tags.outline(user, person.id)

      assert ids(root.tasks) == Enum.sort([direct.id, both.id])
      assert Enum.map(root.children, & &1.tag.name) == ["Family"]

      assert [%{tag: %{name: "Wife"}, tasks: wife_tasks, children: []}] =
               hd(root.children).children

      assert ids(wife_tasks) == Enum.sort([both.id, via_project.id, in_inbox.id])
      assert MapSet.size(unavailable) == 0
      refute kid.id in Enum.map(root.children, & &1.tag.id)
    end

    test "a dropped tag's own outline still shows its tasks", %{user: user} do
      old = tag!(user, "Old")
      task = task!(user, tags: [old])
      {:ok, _} = Tags.set_tag_state(user, old.id, :dropped, command())

      %{root: root, unavailable: unavailable} = Tags.outline(user, old.id)
      assert ids(root.tasks) == [task.id]
      assert MapSet.member?(unavailable, task.id)
    end

    test "untagged tasks have no tags of their own or from a project", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{"title" => "Garden"}, command())
      home = tag!(user, "Home")
      {:ok, _} = Tags.tag_project(user, project.id, home.id, command())

      inbox = task!(user, inbox: true)
      _inherits = task!(user, project_id: project.id)
      _tagged = task!(user, tags: [home])

      assert ids(Tags.untagged_tasks(user)) == [inbox.id]
    end

    test "a project view includes its inbox tasks", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{"title" => "Garden"}, command())
      task = task!(user, project_id: project.id, inbox: true)

      assert ids(Tasks.list_project_tasks(user, project.id)) == [task.id]
    end

    test "outlines stay inside one user", %{user: user, other: other} do
      theirs = tag!(other, "Theirs")
      assert Tags.outline(user, theirs.id) == nil
    end
  end

  defp ids(tasks), do: tasks |> Enum.map(& &1.id) |> Enum.sort()

  defp tag!(user, name, parent \\ nil) do
    attrs = %{"name" => name, "parent_id" => parent && parent.id}
    {:ok, tag} = Tags.create_tag(user, attrs, command())
    tag
  end

  defp task!(user, opts \\ []) do
    attrs = %{
      "title" => "Call",
      "inbox" => Keyword.get(opts, :inbox, false),
      "project_id" => opts[:project_id]
    }

    {:ok, task} = Tasks.create_task(user, attrs, command())

    for tag <- Keyword.get(opts, :tags, []) do
      {:ok, _} = Tags.tag_task(user, task.id, tag.id, command())
    end

    task
  end

  defp live_tag_ids(task) do
    Repo.all(
      from l in TaskTag,
        where: l.task_id == ^task.id and is_nil(l.discarded_at),
        select: l.tag_id
    )
  end

  defp changes(user, entity_id) do
    Repo.aggregate(
      from(c in Change, where: c.user_id == ^user.id and c.entity_id == ^entity_id),
      :count
    )
  end

  defp command, do: Ecto.UUID.generate()
end
