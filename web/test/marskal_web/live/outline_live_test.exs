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
    {:ok, view, _html} = live(ctx.conn, ~p"/")

    assert view |> element("#task-#{child.id} .crumb") |> render() =~ "Paint"
    refute has_element?(view, "#task-#{a.id} .crumb")
  end

  test "the inspector shows a subtask's parent and what it inherits", ctx do
    [a] = add(ctx, ["Paint"])

    {:ok, _} =
      Tasks.update_task(ctx.user, a.id, %{due_at: ~U[2026-12-01 16:00:00Z]}, command_id())

    child = add(ctx, "Buy paint", a)
    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

    view |> element("#task-#{child.id} button.select") |> render_click()

    assert view |> element("#inspector-task-parent") |> render() =~ "Paint"
    assert view |> element("#inspector-task-dates") |> render() =~ "From above: 1 Dec"
    refute has_element?(view, "#inspector-task-resolved-above")

    {:ok, _} = Tasks.drop_task(ctx.user, a.id, command_id())
    assert has_element?(view, "#inspector-task-resolved-above")
  end

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

  defp rows(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#project-tasks li.task-row")
    |> LazyHTML.attribute("data-inspect-id")
  end

  defp command_id, do: Ecto.UUID.generate()
end
