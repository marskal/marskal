defmodule MarskalWeb.OutlineLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Projects
  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, project} = Projects.create_project(user, %{"title" => "House"}, command_id())
    %{conn: log_in_user(conn, user), user: user, project: project}
  end

  test "a project shows subtasks under their parent, a level in", ctx do
    [a, b] = add(ctx, ["Paint", "Tidy"])
    child = add(ctx, "Buy paint", a)

    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

    assert rows(view) == [a.id, child.id, b.id]
    assert has_element?(view, "#task-#{child.id}[data-depth='1']")
    assert has_element?(view, "#task-#{a.id} .disclosure button[aria-expanded='true']")
    refute has_element?(view, "#task-#{b.id} .disclosure button")
  end

  test "the keys indent, outdent, and move among siblings", ctx do
    [a, b, c] = add(ctx, ["A", "B", "C"])
    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

    render_hook(view, "outline-indent", %{"id" => b.id})
    assert Tasks.get_task(ctx.user, b.id).parent_id == a.id
    assert has_element?(view, "#task-#{b.id}[data-depth='1']")

    render_hook(view, "outline-down", %{"id" => a.id})
    assert rows(view) == [c.id, a.id, b.id]

    render_hook(view, "outline-up", %{"id" => a.id})
    render_hook(view, "outline-outdent", %{"id" => b.id})
    assert rows(view) == [a.id, b.id, c.id]
    assert Tasks.get_task(ctx.user, b.id).parent_id == nil

    # The first sibling has nothing to indent under; the key does nothing.
    render_hook(view, "outline-indent", %{"id" => a.id})
    refute render(view) =~ "Could not move"
  end

  test "a drop places the task under its parent, after its sibling", ctx do
    [a, b, c] = add(ctx, ["A", "B", "C"])
    child = add(ctx, "Child", a)
    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

    render_hook(view, "outline-place", %{
      "id" => c.id,
      "parent_id" => a.id,
      "after_id" => child.id
    })

    assert rows(view) == [a.id, child.id, c.id, b.id]
    assert has_element?(view, "#task-#{c.id}[data-depth='1']")

    render_hook(view, "outline-place", %{"id" => a.id, "parent_id" => nil, "after_id" => b.id})
    assert rows(view) == [b.id, a.id, child.id, c.id]

    # Under its own subtask is refused, and says so.
    render_hook(view, "outline-place", %{"id" => a.id, "parent_id" => c.id, "after_id" => nil})
    assert render(view) =~ "Could not move that task there."
    assert rows(view) == [b.id, a.id, child.id, c.id]
  end

  test "collapsing hides the subtasks and tells the browser what to keep", ctx do
    [a] = add(ctx, ["Paint"])
    child = add(ctx, "Buy paint", a)
    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

    view |> element("#task-#{a.id} .disclosure button") |> render_click()

    refute has_element?(view, "#task-#{child.id}")
    assert_push_event(view, "outline-collapsed", %{ids: [id]})
    assert id == a.id

    # A new page gets the saved set from the hook.
    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")
    assert has_element?(view, "#task-#{child.id}")
    render_hook(view, "outline-collapsed", %{"ids" => [a.id]})
    refute has_element?(view, "#task-#{child.id}")
  end

  test "completing a parent keeps its subtree on screen, resolved", ctx do
    [a] = add(ctx, ["Paint"])
    child = add(ctx, "Buy paint", a)
    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

    view |> element("#task-#{a.id} .check") |> render_click()

    assert has_element?(view, "#task-#{a.id}.is-resolved")
    assert has_element?(view, "#task-#{child.id}.is-resolved")

    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")
    refute has_element?(view, "#task-#{child.id}")
  end

  test "a flat list names a subtask's parent", ctx do
    [a] = add(ctx, ["Paint"])
    child = add(ctx, "Buy paint", a)
    {:ok, view, _html} = live(ctx.conn, ~p"/tags/untagged")

    assert view |> element("#task-#{child.id} .crumb") |> render() =~ "Paint"
    refute has_element?(view, "#task-#{a.id} .crumb")
  end

  test "open tasks nests subtasks under their parent, newest first on top", ctx do
    [a, b] = add(ctx, ["Paint", "Tidy"])
    first = add(ctx, "Buy paint", a)
    second = add(ctx, "Sand", a)
    {:ok, other} = Tasks.create_task(ctx.user, %{title: "Call", inbox: false}, command_id())

    {:ok, view, _html} = live(ctx.conn, ~p"/open")

    assert rows(view, "#open-tasks") == [other.id, b.id, a.id, first.id, second.id]
    assert has_element?(view, "#task-#{first.id}[data-depth='1']")
    refute has_element?(view, "#task-#{first.id} .crumb")
    refute has_element?(view, "#open-tasks[data-outline]")

    render_hook(view, "outline-toggle", %{"id" => a.id})
    assert rows(view, "#open-tasks") == [other.id, b.id, a.id]
  end

  test "open tasks shows a parent tag state hides above its subtask", ctx do
    [a] = add(ctx, ["Paint"])
    child = add(ctx, "Buy paint", a)
    {:ok, tag} = Marskal.Tags.create_tag(ctx.user, %{name: "Later"}, command_id())
    {:ok, _} = Marskal.Tags.update_tag(ctx.user, tag.id, %{state: :on_hold}, command_id())
    {:ok, _} = Marskal.Tags.tag_task(ctx.user, a.id, tag.id, command_id())

    {:ok, view, _html} = live(ctx.conn, ~p"/open")

    assert rows(view, "#open-tasks") == [a.id, child.id]
    assert has_element?(view, "#task-#{a.id}.is-unavailable")
    refute has_element?(view, "#task-#{child.id}.is-unavailable")
  end

  test "the inspector shows a subtask's parent and what it inherits", ctx do
    [a] = add(ctx, ["Paint"])
    # 1 December next year: never within a week of today, so the label is
    # the date with its year, not Tomorrow or a weekday.
    year = Marskal.Dates.today("Europe/Copenhagen").year + 1
    due = DateTime.new!(Date.new!(year, 12, 1), ~T[16:00:00], "Etc/UTC")
    {:ok, _} = Tasks.update_task(ctx.user, a.id, %{due_at: due}, command_id())

    child = add(ctx, "Buy paint", a)
    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

    view |> element("#task-#{child.id} button.select") |> render_click()

    assert view |> element("#inspector-task-parent") |> render() =~ "Paint"
    assert view |> element("#inspector-task-dates") |> render() =~ "From above: 1 Dec #{year}"
    refute has_element?(view, "#inspector-task-resolved-above")

    {:ok, _} = Tasks.drop_task(ctx.user, a.id, command_id())
    assert has_element?(view, "#inspector-task-resolved-above")
  end

  describe "a task added inline" do
    test "o adds below, and Enter opens the next row below the new task", ctx do
      [a, b] = add(ctx, ["A", "B"])
      {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

      render_hook(view, "inline-new", %{"id" => a.id, "where" => "below"})
      assert has_element?(view, "#task-#{a.id} + #task-new input[name=title]")

      view |> form("#task-new-form", %{"title" => "One"}) |> render_submit()
      view |> form("#task-new-form", %{"title" => "Two"}) |> render_submit()

      [one, two] = Enum.map(["One", "Two"], &find(ctx, &1))
      assert rows(view) == [a.id, one.id, two.id, b.id]
      assert has_element?(view, "#task-#{two.id} + #task-new")

      render_hook(view, "inline-cancel", %{})
      refute has_element?(view, "#task-new")
      assert_push_event(view, "outline-focus", %{id: id})
      assert id == two.id
    end

    test "O adds above, as a sibling at the same depth", ctx do
      [a] = add(ctx, ["A"])
      child = add(ctx, "Child", a)
      {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

      render_hook(view, "inline-new", %{"id" => child.id, "where" => "above"})
      assert has_element?(view, "#task-new[style*='--depth: 1'] + #task-#{child.id}")
      view |> form("#task-new-form", %{"title" => "Before"}) |> render_submit()

      before = find(ctx, "Before")
      assert before.parent_id == a.id
      assert rows(view) == [a.id, before.id, child.id]
    end

    test "below an open parent, the new task is its first subtask", ctx do
      [a, b] = add(ctx, ["A", "B"])
      child = add(ctx, "Child", a)
      {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

      render_hook(view, "inline-new", %{"id" => a.id, "where" => "below"})
      view |> form("#task-new-form", %{"title" => "First"}) |> render_submit()

      first = find(ctx, "First")
      assert first.parent_id == a.id
      assert rows(view) == [a.id, first.id, child.id, b.id]
    end

    test "an empty row saves nothing and closes", ctx do
      [a] = add(ctx, ["A"])
      {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

      render_hook(view, "inline-new", %{"id" => a.id, "where" => "below"})
      render_hook(view, "inline-blur", %{"value" => "  "})
      refute has_element?(view, "#task-new")

      render_hook(view, "inline-new", %{"id" => a.id, "where" => "below"})
      view |> form("#task-new-form", %{title: ""}) |> render_submit()
      refute has_element?(view, "#task-new")
      assert rows(view) == [a.id]
    end

    test "leaving the title saves the task and opens it in the inspector", ctx do
      [a] = add(ctx, ["A"])
      {:ok, tag} = Marskal.Tags.create_tag(ctx.user, %{name: "Errand"}, command_id())
      {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

      view |> element("#task-#{a.id} button.select") |> render_click()
      assert has_element?(view, "#inspector-task")

      render_hook(view, "inline-new", %{"id" => a.id, "where" => "below"})

      assert has_element?(view, "#app-shell.is-inspector-open")
      assert has_element?(view, "#inspector-new-task")
      assert has_element?(view, "#inspector-new-task-hint", "Leaving the title saves the task.")
      refute has_element?(view, "#inspector-task")
      refute has_element?(view, "#inspector-new-task-url")

      view |> form("#task-new-form", %{title: "Shop"}) |> render_change()
      assert has_element?(view, "#inspector-new-task-title[value='Shop']")

      render_hook(view, "inline-blur", %{"value" => "Shop"})

      task = find(ctx, "Shop")
      assert task.project_id == ctx.project.id
      assert rows(view) == [a.id, task.id]
      refute has_element?(view, "#task-new")
      refute has_element?(view, "#inspector-new-task")
      assert has_element?(view, "#inspector-task-title[value='Shop']")

      view |> element("#inspector-task-tags-query") |> render_change(%{"tag_query" => "err"})

      view
      |> element("#inspector-task-tags-picker button.suggestion", "Errand")
      |> render_click()

      assert find(ctx, "Shop").title == "Shop"
      assert tag.id in task_tag_ids(ctx, find(ctx, "Shop"))
    end

    test "Enter in the inspector adds the task and opens the next row", ctx do
      [a] = add(ctx, ["A"])
      {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")
      render_hook(view, "inline-new", %{"id" => a.id, "where" => "below"})

      view |> form("#inspector-new-task-form", %{title: "From the inspector"}) |> render_submit()

      task = find(ctx, "From the inspector")
      assert task.project_id == ctx.project.id
      assert has_element?(view, "#task-#{task.id} + #task-new")
      assert has_element?(view, "#inspector-new-task")
      refute has_element?(view, "#inspector-task")
    end

    test "an empty title in the inspector does not add the task", ctx do
      [a] = add(ctx, ["A"])
      {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")
      render_hook(view, "inline-new", %{"id" => a.id, "where" => "below"})

      view |> form("#inspector-new-task-form", %{title: "  "}) |> render_submit()

      refute has_element?(view, "#task-new")
      refute has_element?(view, "#inspector-new-task")
      assert rows(view) == [a.id]
    end

    test "cancelling the new task clears its inspector", ctx do
      [a] = add(ctx, ["A"])
      {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")
      render_hook(view, "inline-new", %{"id" => a.id, "where" => "below"})
      assert has_element?(view, "#inspector-new-task")

      render_hook(view, "inline-cancel", %{})
      refute has_element?(view, "#task-new")
      refute has_element?(view, "#inspector-new-task")
    end

    test "the inbox adds inline too", ctx do
      {:ok, a} = Tasks.create_task(ctx.user, %{"title" => "A"}, command_id())
      {:ok, view, _html} = live(ctx.conn, ~p"/inbox")

      render_hook(view, "inline-new", %{"id" => a.id, "where" => "below"})
      view |> form("#task-new-form", %{"title" => "Next"}) |> render_submit()

      next = find(ctx, "Next")
      assert next.inbox
      assert rows(view, "#inbox-tasks") == [a.id, next.id]
    end
  end

  defp find(ctx, title),
    do: Marskal.Repo.get_by!(Marskal.Tasks.Task, user_id: ctx.user.id, title: title)

  defp add(ctx, titles) when is_list(titles), do: Enum.map(titles, &add(ctx, &1, nil))

  defp add(ctx, title, parent) do
    attrs = %{
      "title" => title,
      "project_id" => ctx.project.id,
      "parent_id" => parent && parent.id
    }

    {:ok, task} = Tasks.create_task(ctx.user, attrs, command_id())
    task
  end

  defp rows(view, list \\ "#project-tasks") do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#{list} li.task-row")
    |> LazyHTML.attribute("data-inspect-id")
  end

  defp task_tag_ids(ctx, task) do
    tree = Marskal.Tags.tree(ctx.user)
    [entries] = Map.values(Marskal.Tags.effective_tags(ctx.user, [task], tree))
    for %{tag: tag, inherited: false} <- entries, do: tag.id
  end

  defp command_id, do: Ecto.UUID.generate(version: 7)
end
