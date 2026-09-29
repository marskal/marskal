defmodule Marskal.OutlineTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Changes.Change
  alias Marskal.Projects
  alias Marskal.Repo
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, project} = Projects.create_project(user, %{"title" => "House"}, command_id())
    %{user: user, other: AccountsFixtures.user_fixture(), project: project}
  end

  describe "placing new tasks" do
    test "a project lists new tasks at the bottom", %{user: user, project: project} do
      [a, b, c] = add(user, project, ["A", "B", "C"])

      assert ids(Tasks.list_project_tasks(user, project.id)) == [a.id, b.id, c.id]
    end

    test "the inbox lists new tasks at the top", %{user: user} do
      {:ok, a} = Tasks.create_task(user, %{"title" => "A"}, command_id())
      {:ok, b} = Tasks.create_task(user, %{"title" => "B"}, command_id())

      assert ids(Tasks.list_inbox(user)) == [b.id, a.id]
    end

    test "after_id puts a new task right after that sibling", %{user: user, project: project} do
      [a, b] = add(user, project, ["A", "B"])
      {:ok, new} = create(user, project, %{"title" => "New", "after_id" => a.id})

      assert ids(Tasks.list_project_tasks(user, project.id)) == [a.id, new.id, b.id]
    end

    test "a subtask lives where its parent does", %{user: user, project: project} do
      [parent] = add(user, project, ["Parent"])

      {:ok, child} =
        Tasks.create_task(
          user,
          %{"title" => "Child", "parent_id" => parent.id, "inbox" => true},
          command_id()
        )

      assert child.parent_id == parent.id
      assert child.project_id == project.id
      refute child.inbox
      assert_outline!()
    end

    test "a subtask needs a parent the user owns", %{user: user, other: other} do
      {:ok, theirs} = Tasks.create_task(other, %{"title" => "Theirs"}, command_id())

      assert {:error, changeset} =
               Tasks.create_task(
                 user,
                 %{"title" => "Mine", "parent_id" => theirs.id},
                 command_id()
               )

      assert "must be one of your tasks" in errors_on(changeset).parent_id
    end

    test "a client's rank is kept, and a malformed one refused", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{"title" => "A", "rank" => "Vx"}, command_id())
      assert task.rank == "Vx"

      assert {:error, changeset} =
               Tasks.create_task(user, %{"title" => "B", "rank" => "V0"}, command_id())

      assert "is not a valid rank" in errors_on(changeset).rank
    end
  end

  describe "reordering" do
    test "a task moves first, or after any sibling", %{user: user, project: project} do
      [a, b, c] = add(user, project, ["A", "B", "C"])

      {:ok, _} = Tasks.place_task(user, c.id, nil, nil, command_id())
      assert ids(Tasks.list_project_tasks(user, project.id)) == [c.id, a.id, b.id]

      {:ok, _} = Tasks.place_task(user, c.id, nil, a.id, command_id())
      assert ids(Tasks.list_project_tasks(user, project.id)) == [a.id, c.id, b.id]

      {:ok, _} = Tasks.place_task(user, a.id, nil, b.id, command_id())
      assert ids(Tasks.list_project_tasks(user, project.id)) == [c.id, b.id, a.id]
    end

    test "a move is one patch of rank", %{user: user, project: project} do
      [a, _b, c] = add(user, project, ["A", "B", "C"])
      before = Repo.aggregate(Change, :count)

      {:ok, _} = Tasks.place_task(user, a.id, nil, c.id, command_id())

      assert Repo.aggregate(Change, :count) == before + 1
      assert %Change{patch: patch} = Repo.one(from c in Change, order_by: [desc: c.id], limit: 1)
      assert Map.keys(patch) == ["rank"]
    end

    test "after_id must be a sibling", %{user: user, project: project} do
      [a, b] = add(user, project, ["A", "B"])
      {:ok, child} = create(user, project, %{"title" => "Child", "parent_id" => a.id})

      assert {:error, :not_a_sibling} = Tasks.place_task(user, b.id, a.id, b.id, command_id())

      assert {:error, :not_a_sibling} =
               Tasks.place_task(user, child.id, nil, child.id, command_id())
    end
  end

  describe "indent and outdent" do
    test "indent makes a task the last subtask of the one above", %{user: user, project: project} do
      [a, b, c] = add(user, project, ["A", "B", "C"])
      {:ok, _} = Tasks.indent_task(user, b.id, command_id())
      {:ok, c} = Tasks.indent_task(user, c.id, command_id())

      assert c.parent_id == a.id
      assert children(a) == [b.id, c.id]
      assert_outline!()
    end

    test "the first sibling cannot indent", %{user: user, project: project} do
      [a] = add(user, project, ["A"])
      assert {:error, :first} = Tasks.indent_task(user, a.id, command_id())
    end

    test "outdent puts a task right after its parent", %{user: user, project: project} do
      [a, b] = add(user, project, ["A", "B"])
      {:ok, child} = create(user, project, %{"title" => "Child", "parent_id" => a.id})

      {:ok, child} = Tasks.outdent_task(user, child.id, command_id())

      assert child.parent_id == nil
      assert ids(Tasks.list_project_tasks(user, project.id)) == [a.id, child.id, b.id]
    end

    test "a top-level task cannot outdent", %{user: user, project: project} do
      [a] = add(user, project, ["A"])
      assert {:error, :top_level} = Tasks.outdent_task(user, a.id, command_id())
    end
  end

  describe "structure" do
    test "a task cannot go under itself or its own subtask", %{user: user, project: project} do
      [a] = add(user, project, ["A"])
      {:ok, child} = create(user, project, %{"title" => "Child", "parent_id" => a.id})

      {:ok, grandchild} =
        create(user, project, %{"title" => "Grandchild", "parent_id" => child.id})

      assert {:error, :cycle} = Tasks.place_task(user, a.id, a.id, nil, command_id())
      assert {:error, :cycle} = Tasks.place_task(user, a.id, grandchild.id, nil, command_id())
      assert Repo.get!(Task, a.id).parent_id == nil
    end

    test "a subtree moves with its root, and leaves the parent behind", %{
      user: user,
      project: project
    } do
      {:ok, garden} = Projects.create_project(user, %{"title" => "Garden"}, command_id())
      [a] = add(user, project, ["A"])
      {:ok, b} = create(user, project, %{"title" => "B", "parent_id" => a.id})
      {:ok, c} = create(user, project, %{"title" => "C", "parent_id" => b.id})
      command_id = command_id()

      {:ok, b} = Tasks.move_task(user, b.id, garden.id, command_id)

      assert b.parent_id == nil
      assert b.project_id == garden.id
      assert Repo.get!(Task, c.id).project_id == garden.id
      assert Repo.get!(Task, c.id).parent_id == b.id
      assert children(a) == []
      assert_outline!()

      # The root and each subtask are one change row apiece; a replay adds none.
      count = Repo.aggregate(Change, :count)
      {:ok, _} = Tasks.move_task(user, b.id, garden.id, command_id)
      assert Repo.aggregate(Change, :count) == count
    end

    test "moving to where the task already is keeps its parent", %{user: user, project: project} do
      [a] = add(user, project, ["A"])
      {:ok, b} = create(user, project, %{"title" => "B", "parent_id" => a.id})

      {:ok, b} = Tasks.move_task(user, b.id, project.id, command_id())

      assert b.parent_id == a.id
    end

    test "placing under a parent in another project moves the subtree there",
         %{user: user, project: project} do
      {:ok, garden} = Projects.create_project(user, %{"title" => "Garden"}, command_id())
      [a] = add(user, project, ["A"])
      {:ok, child} = create(user, project, %{"title" => "Child", "parent_id" => a.id})
      [target] = add(user, garden, ["Target"])

      {:ok, a} = Tasks.place_task(user, a.id, target.id, nil, command_id())

      assert a.project_id == garden.id
      assert Repo.get!(Task, child.id).project_id == garden.id
      assert_outline!()
    end

    test "deleting a task discards its subtree", %{user: user, project: project} do
      [a] = add(user, project, ["A"])
      {:ok, child} = create(user, project, %{"title" => "Child", "parent_id" => a.id})

      {:ok, grandchild} =
        create(user, project, %{"title" => "Grandchild", "parent_id" => child.id})

      {:ok, _} = Tasks.delete_task(user, a.id, command_id())

      assert Repo.get!(Task, grandchild.id).discarded_at
      assert Repo.get!(Task, child.id).discarded_at
      assert_outline!()
    end

    test "another user's task is not a place to put yours", %{user: user, other: other} do
      {:ok, mine} = Tasks.create_task(user, %{"title" => "Mine"}, command_id())
      {:ok, theirs} = Tasks.create_task(other, %{"title" => "Theirs"}, command_id())

      assert {:error, :not_found} = Tasks.place_task(user, mine.id, theirs.id, nil, command_id())
      assert {:error, :not_found} = Tasks.place_task(other, mine.id, nil, nil, command_id())
    end
  end

  describe "resolving what is above" do
    test "a resolved task resolves its subtree until it reopens", %{user: user, project: project} do
      [a, other] = add(user, project, ["A", "Other"])
      {:ok, child} = create(user, project, %{"title" => "Child", "parent_id" => a.id})

      {:ok, grandchild} =
        create(user, project, %{"title" => "Grandchild", "parent_id" => child.id})

      {:ok, _} = Tasks.complete_task(user, a.id, command_id())

      assert ids(Tasks.list_project_tasks(user, project.id)) == [other.id]
      assert Repo.get!(Task, grandchild.id).state == :to_do

      {:ok, _} = Tasks.reopen_task(user, a.id, command_id())

      assert Enum.sort(ids(Tasks.list_project_tasks(user, project.id))) ==
               Enum.sort([a.id, other.id, child.id, grandchild.id])
    end

    test "a dropped parent resolves its subtree in every list", %{user: user} do
      {:ok, a} = Tasks.create_task(user, %{"title" => "A", "inbox" => false}, command_id())

      {:ok, child} =
        Tasks.create_task(
          user,
          %{"title" => "Child", "parent_id" => a.id, "planned_at" => DateTime.utc_now()},
          command_id()
        )

      {:ok, tag} = Marskal.Tags.create_tag(user, %{"name" => "Home"}, command_id())
      {:ok, _} = Marskal.Tags.tag_task(user, child.id, tag.id, command_id())
      today = Marskal.Dates.today(user.timezone)

      assert child.id in ids(Tasks.list_open(user))
      assert child.id in ids(Tasks.list_planned(user, today))

      {:ok, _} = Tasks.drop_task(user, a.id, command_id())

      refute child.id in ids(Tasks.list_open(user))
      refute child.id in ids(Tasks.list_planned(user, today))
      assert Marskal.Tags.outline(user, tag.id).root.tasks == []
    end

    test "a resolved project resolves its tasks", %{user: user, project: project} do
      [a] = add(user, project, ["A"])
      assert a.id in ids(Tasks.list_open(user))

      {:ok, _} = Projects.complete_project(user, project.id, command_id())

      refute a.id in ids(Tasks.list_open(user))
      assert Tasks.list_project_tasks(user, project.id) == []
      refute a.id in ids(Marskal.Tags.untagged_tasks(user))

      {:ok, _} = Projects.reopen_project(user, project.id, command_id())
      assert a.id in ids(Tasks.list_open(user))
    end
  end

  describe "the database" do
    test "refuses a subtask that is not where its parent is", %{user: user, project: project} do
      [a] = add(user, project, ["A"])
      {:ok, child} = create(user, project, %{"title" => "Child", "parent_id" => a.id})

      Repo.update_all(from(t in Task, where: t.id == ^child.id),
        set: [project_id: nil, inbox: true]
      )

      assert_raise Postgrex.Error, ~r/tasks_parent_location/, &assert_outline!/0
    end

    test "refuses a cycle", %{user: user, project: project} do
      [a] = add(user, project, ["A"])
      {:ok, child} = create(user, project, %{"title" => "Child", "parent_id" => a.id})

      Repo.update_all(from(t in Task, where: t.id == ^a.id), set: [parent_id: child.id])

      assert_raise Postgrex.Error, ~r/tasks_parent_cycle/, &assert_outline!/0
    end

    test "refuses a live subtask under a discarded task", %{user: user, project: project} do
      [a] = add(user, project, ["A"])
      {:ok, _child} = create(user, project, %{"title" => "Child", "parent_id" => a.id})

      Repo.update_all(from(t in Task, where: t.id == ^a.id),
        set: [discarded_at: DateTime.utc_now()]
      )

      assert_raise Postgrex.Error, ~r/tasks_parent_live/, &assert_outline!/0
    end
  end

  # The outline trigger runs at commit, which the test sandbox never
  # reaches. Making it immediate runs the checks queued so far.
  defp assert_outline! do
    Repo.query!("SET CONSTRAINTS tasks_outline IMMEDIATE")
    Repo.query!("SET CONSTRAINTS tasks_outline DEFERRED")
    :ok
  end

  defp add(user, project, titles) do
    for title <- titles do
      {:ok, task} = create(user, project, %{"title" => title})
      task
    end
  end

  defp create(user, project, attrs),
    do: Tasks.create_task(user, Map.put(attrs, "project_id", project.id), command_id())

  defp children(task), do: task |> Marskal.Tasks.Outline.children() |> ids()

  defp ids(tasks), do: Enum.map(tasks, & &1.id)

  defp command_id, do: Ecto.UUID.generate()
end
