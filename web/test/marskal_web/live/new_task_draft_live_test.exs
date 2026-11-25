defmodule MarskalWeb.NewTaskDraftLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Projects
  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "the inbox's add field" do
    test "a typed title shows in the inspector, an empty one does not", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/inbox")
      refute has_element?(view, "#app-shell.is-inspector-open")

      render_hook(view, "draft-title", %{"title" => " ", "form" => "new-task"})
      refute has_element?(view, "#inspector-new-task")

      render_hook(view, "draft-title", %{"title" => "Call", "form" => "new-task"})
      assert has_element?(view, "#app-shell.is-inspector-open")
      assert has_element?(view, "#inspector-new-task-form[data-submit-to='new-task']")
      assert has_element?(view, "#inspector-new-task-title[value='Call']")

      view |> form("#inspector-new-task-form", %{title: "Call Bo"}) |> render_change()
      assert_push_event(view, "inline-title", %{title: "Call Bo"})
    end

    test "leaving the title saves the task, and the inspector edits it", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/inbox")
      render_hook(view, "draft-title", %{"title" => "Call", "form" => "new-task"})

      view
      |> form("#new-task", task: %{title: "Call"})
      |> render_submit(%{"leave" => "true", "inspector" => "true"})

      [task] = Tasks.list_inbox(ctx.user)
      assert task.title == "Call"
      refute has_element?(view, "#inspector-new-task")
      assert has_element?(view, "#inspector-task-title[value='Call']")
      assert_patched(view, ~p"/inbox?task=#{task.id}")
      assert_push_event(view, "inspector-focus", %{})
    end

    test "leaving for somewhere else does not move focus", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/inbox")
      render_hook(view, "draft-title", %{"title" => "Call", "form" => "new-task"})

      view |> form("#new-task", task: %{title: "Call"}) |> render_submit(%{"leave" => "true"})

      assert has_element?(view, "#inspector-task-title[value='Call']")
      refute_push_event(view, "inspector-focus", _payload)
    end

    test "Enter in the inspector hands the title to the add field", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/inbox")
      render_hook(view, "draft-title", %{"title" => "Call", "form" => "new-task"})

      view |> form("#inspector-new-task-form", %{title: "Call Bo"}) |> render_submit()

      assert_push_event(view, "draft-submit", %{form: "new-task", title: "Call Bo"})
    end

    test "Enter saves the task and the field takes the next", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/inbox")
      render_hook(view, "draft-title", %{"title" => "Call", "form" => "new-task"})

      view |> form("#new-task", task: %{title: "Call"}) |> render_submit()

      assert [%{title: "Call"}] = Tasks.list_inbox(ctx.user)
      assert_push_event(view, "draft-clear", %{form: "new-task"})
      refute has_element?(view, "#inspector-new-task")
      refute has_element?(view, "#inspector-task")
      refute has_element?(view, "#app-shell.is-inspector-open")
    end

    test "cancelling saves nothing and clears the field", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/inbox")
      render_hook(view, "draft-title", %{"title" => "Call", "form" => "new-task"})

      view |> element("#app-shell .app-inspector__close") |> render_click()

      assert_push_event(view, "draft-clear", %{form: "new-task"})
      refute has_element?(view, "#inspector-new-task")
      assert Tasks.list_inbox(ctx.user) == []
    end
  end

  test "a project's add field files the task in the project", ctx do
    {:ok, project} = Projects.create_project(ctx.user, %{"title" => "House"}, command_id())
    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{project.id}")
    render_hook(view, "draft-title", %{"title" => "Sweep", "form" => "new-project-task"})
    assert has_element?(view, "#inspector-new-task-form[data-submit-to='new-project-task']")

    view
    |> form("#new-project-task", task: %{title: "Sweep"})
    |> render_submit(%{"leave" => "true"})

    [task] = Tasks.list_project_tasks(ctx.user, project.id)
    assert task.title == "Sweep"
    assert has_element?(view, "#inspector-task-title[value='Sweep']")
  end

  test "a tag's add field tags the task", ctx do
    {:ok, tag} = Marskal.Tags.create_tag(ctx.user, %{name: "Errand"}, command_id())
    {:ok, view, _html} = live(ctx.conn, ~p"/tags/#{tag.id}")
    render_hook(view, "draft-title", %{"title" => "Post", "form" => "new-tag-task"})
    assert has_element?(view, "#inspector-new-task-form[data-submit-to='new-tag-task']")

    view |> form("#new-tag-task", task: %{title: "Post"}) |> render_submit(%{"leave" => "true"})

    assert has_element?(view, "#inspector-task-title[value='Post']")
    assert has_element?(view, "#inspector-task-tags", "Errand")
  end

  defp command_id, do: Ecto.UUID.generate(version: 7)
end
