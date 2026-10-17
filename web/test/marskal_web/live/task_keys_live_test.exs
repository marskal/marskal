defmodule MarskalWeb.TaskKeysLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Accounts
  alias Marskal.Projects
  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, project} = Projects.create_project(user, %{title: "House"}, command_id())
    %{conn: log_in_user(conn, user), user: user, project: project}
  end

  test "check, drop, and flag act on the task, and the shell names the map", ctx do
    task = add(ctx, "Paint")
    {:ok, view, html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")

    assert html =~ ~s(data-keymap="standard")
    assert has_element?(view, "#new-project-task[data-new-task] input[type='text']")

    render_hook(view, "task-check", %{"id" => task.id})
    assert Tasks.get_task(ctx.user, task.id).state == :done
    assert has_element?(view, "#task-#{task.id}.is-resolved")

    render_hook(view, "task-check", %{"id" => task.id})
    assert Tasks.get_task(ctx.user, task.id).state == :to_do
    refute has_element?(view, "#task-#{task.id}.is-resolved")

    render_hook(view, "task-flag", %{"id" => task.id})
    assert Tasks.get_task(ctx.user, task.id).flagged
    render_hook(view, "task-flag", %{"id" => task.id})
    refute Tasks.get_task(ctx.user, task.id).flagged

    assert render_hook(view, "task-drop", %{"id" => task.id}) =~ "Dropped “Paint”."
    assert Tasks.get_task(ctx.user, task.id).state == :dropped
    assert has_element?(view, "#task-#{task.id}.is-resolved")

    render_hook(view, "task-check", %{"id" => task.id})
    assert Tasks.get_task(ctx.user, task.id).state == :to_do
  end

  test "the key reference shows the user's map", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")
    assert has_element?(view, "#keys-help", "Keyboard shortcuts")
    refute has_element?(view, "#keys-help kbd", "dd")

    {:ok, _} = Accounts.update_preferences(ctx.user, %{keymap: :vim}, command_id())
    {:ok, view, html} = live(ctx.conn, ~p"/projects/#{ctx.project.id}")
    assert html =~ ~s(data-keymap="vim")
    assert has_element?(view, "#keys-help kbd", "dd")
  end

  test "a list without an outline still takes the keys", ctx do
    task = add(ctx, "Paint")
    {:ok, view, _html} = live(ctx.conn, ~p"/tags/untagged")

    render_hook(view, "task-flag", %{"id" => task.id})
    assert Tasks.get_task(ctx.user, task.id).flagged
  end

  test "someone else's task is left alone", ctx do
    other = user_fixture()
    {:ok, task} = Tasks.create_task(other, %{title: "Theirs"}, command_id())
    {:ok, view, _html} = live(ctx.conn, ~p"/inbox")

    render_hook(view, "task-check", %{"id" => task.id})
    assert Tasks.get_task(other, task.id).state == :to_do
    assert render(view) =~ "Could not update task."
  end

  defp add(ctx, title) do
    {:ok, task} =
      Tasks.create_task(
        ctx.user,
        %{"title" => title, "project_id" => ctx.project.id},
        command_id()
      )

    task
  end

  defp command_id, do: Ecto.UUID.generate(version: 7)
end
