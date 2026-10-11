defmodule MarskalWeb.TagsLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Projects
  alias Marskal.Tags
  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "sidebar" do
    test "lists visible tags and hides dropped subtrees", %{conn: conn, user: user} do
      person = tag!(user, "Person")
      tag!(user, "Wife", person)
      old = tag!(user, "Old")
      tag!(user, "Friend", old)
      {:ok, _} = Tags.set_tag_state(user, old.id, :dropped, command())

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#sidebar-tags a", "Person")
      assert has_element?(view, "#sidebar-tags a", "Wife")
      refute has_element?(view, "#sidebar-tags a", "Old")
      refute has_element?(view, "#sidebar-tags a", "Friend")
    end

    test "a new tag opens its page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#new-root-tag")
      view |> element("button[aria-label='New tag']") |> render_click()

      {:ok, _tag_view, html} =
        view
        |> form("#new-root-tag", tag: %{name: "Waiting"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Waiting"
    end
  end

  describe "tag page" do
    test "shows the tag's tasks, then one group per child tag", %{conn: conn, user: user} do
      person = tag!(user, "Person")
      wife = tag!(user, "Wife", person)
      task!(user, "Call Mum", tags: [person])
      task!(user, "Flowers", tags: [wife], inbox: true)

      {:ok, view, _html} = live(conn, ~p"/tags/#{person.id}")

      assert has_element?(view, "#tag-tasks-#{person.id}", "Call Mum")
      assert has_element?(view, "#tag-group-#{wife.id} h2 a", "Wife")
      assert has_element?(view, "#tag-tasks-#{wife.id}", "Flowers")
      assert has_element?(view, "#tag-tasks-#{wife.id} .mark--inbox")
    end

    test "a done task keeps its row and its group until the view changes", %{
      conn: conn,
      user: user
    } do
      person = tag!(user, "Person")
      wife = tag!(user, "Wife", person)
      flowers = task!(user, "Flowers", tags: [wife])

      {:ok, view, _html} = live(conn, ~p"/tags/#{person.id}")
      view |> element("#task-#{flowers.id} button.check") |> render_click()

      assert has_element?(view, "#tag-tasks-#{wife.id} li.is-resolved", "Flowers")

      {:ok, view, _html} = live(conn, ~p"/tags/#{person.id}")
      refute has_element?(view, "#tag-group-#{wife.id}")
    end

    test "putting it on hold marks its tasks unavailable", %{conn: conn, user: user} do
      waiting = tag!(user, "Waiting")
      task = task!(user, "Reply from Bo", tags: [waiting])

      {:ok, view, _html} = live(conn, ~p"/tags/#{waiting.id}")
      refute has_element?(view, "#task-#{task.id}.is-unavailable")

      view |> element("button", "Put on hold") |> render_click()

      assert has_element?(view, "#task-#{task.id}.is-unavailable")
      assert has_element?(view, "button", "Activate")
    end

    test "a child tag can be added", %{conn: conn, user: user} do
      person = tag!(user, "Person")
      {:ok, view, _html} = live(conn, ~p"/tags/#{person.id}")

      view |> form("#new-child-tag", tag: %{name: "Kid"}) |> render_submit()

      assert has_element?(view, "#sidebar-tags a", "Kid")
    end

    test "another user's tag is not available", %{conn: conn} do
      other = user_fixture()
      theirs = tag!(other, "Theirs")

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/tags/#{theirs.id}")
    end
  end

  test "the untagged page lists tasks without tags", %{conn: conn, user: user} do
    home = tag!(user, "Home")
    task!(user, "Loose end")
    task!(user, "Fix tap", tags: [home])

    {:ok, view, _html} = live(conn, ~p"/tags/untagged")

    assert has_element?(view, "#untagged-tasks", "Loose end")
    refute has_element?(view, "#untagged-tasks", "Fix tap")
  end

  test "task rows show their own and inherited tags", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{"title" => "Garden"}, command())
    home = tag!(user, "Home")
    short = tag!(user, "Short")
    {:ok, _} = Tags.tag_project(user, project.id, home.id, command())
    task = task!(user, "Weed", project_id: project.id, tags: [short])

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#task-#{task.id} .tag-chips li:not(.is-inherited) a", "Short")
    assert has_element?(view, "#task-#{task.id} .tag-chips li.is-inherited a", "Home")
  end

  describe "tag picker" do
    test "adds a suggested tag and removes it", %{conn: conn, user: user} do
      person = tag!(user, "Person")
      wife = tag!(user, "Wife", person)
      task = task!(user, "Anniversary")

      {:ok, view, _html} = live(conn, ~p"/?#{[task: task.id]}")

      view
      |> form("#inspector-task-tags-picker", tag_query: "per/wi")
      |> render_change()

      view
      |> element("#inspector-task-tags-picker button.suggestion", "Wife")
      |> render_click()

      assert has_element?(view, "#inspector-task-tags li[data-tag-id='#{wife.id}']")
      assert has_element?(view, "#task-#{task.id} .tag-chips a", "Wife")

      view
      |> element("#inspector-task-tags button[aria-label='Remove Person › Wife']")
      |> render_click()

      refute has_element?(view, "#inspector-task-tags li[data-tag-id='#{wife.id}']")
    end

    test "Enter adds the first suggestion", %{conn: conn, user: user} do
      waiting = tag!(user, "Waiting")
      task = task!(user, "Reply")

      {:ok, view, _html} = live(conn, ~p"/?#{[task: task.id]}")

      view |> form("#inspector-task-tags-picker", tag_query: "wai") |> render_change()
      view |> form("#inspector-task-tags-picker", tag_query: "wai") |> render_submit()

      assert has_element?(view, "#inspector-task-tags li[data-tag-id='#{waiting.id}']")
    end

    test "creates a tag under the chosen parent", %{conn: conn, user: user} do
      lists = tag!(user, "Lists")
      task = task!(user, "Learn Portuguese")

      {:ok, view, _html} = live(conn, ~p"/?#{[task: task.id]}")

      view |> form("#inspector-task-tags-picker", tag_query: "Someday/maybe") |> render_change()

      view
      |> form("#inspector-task-tags-picker", tag_query: "Someday/maybe", tag_parent: lists.id)
      |> render_submit(%{action: "create"})

      [created] = Tags.list_tags(user) |> Enum.filter(&(&1.parent_id == lists.id))
      assert created.name == "Someday/maybe"
      assert has_element?(view, "#inspector-task-tags li[data-tag-id='#{created.id}']")
    end

    test "tags a project", %{conn: conn, user: user} do
      {:ok, project} = Projects.create_project(user, %{"title" => "Garden"}, command())
      home = tag!(user, "Home")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}?#{[project: project.id]}")

      view |> form("#inspector-project-tags-picker", tag_query: "home") |> render_change()

      view
      |> element("#inspector-project-tags-picker button.suggestion", "Home")
      |> render_click()

      assert has_element?(view, "#inspector-project-tags li[data-tag-id='#{home.id}']")
    end
  end

  describe "tag inspector" do
    test "renames, and deletes the tag", %{conn: conn, user: user} do
      tag = tag!(user, "Wating")

      {:ok, view, _html} = live(conn, ~p"/?#{[tag: tag.id]}")

      view |> form("#inspector-tag", tag: %{name: "Waiting"}) |> render_change()
      assert has_element?(view, "#sidebar-tags a", "Waiting")

      view |> element("#inspector-tag-delete") |> render_click()
      refute has_element?(view, "#sidebar-tags a", "Waiting")
      assert Tags.get_tag(user, tag.id) == nil
    end

    test "cannot move a tag into its own subtree", %{conn: conn, user: user} do
      person = tag!(user, "Person")
      wife = tag!(user, "Wife", person)
      other = tag!(user, "Other")

      {:ok, view, _html} = live(conn, ~p"/?#{[tag: person.id]}")

      assert has_element?(view, "#inspector-tag-parent option[value='#{other.id}']")
      refute has_element?(view, "#inspector-tag-parent option[value='#{wife.id}']")
      refute has_element?(view, "#inspector-tag-parent option[value='#{person.id}']")
    end
  end

  test "opening the inspector keeps the open stream's toggle", %{conn: conn, user: user} do
    task = task!(user, "Anything")

    {:ok, view, _html} = live(conn, ~p"/?#{[unavailable: 1]}")
    view |> element("#task-#{task.id} button.select") |> render_click()

    assert_patch(view, ~p"/?#{[task: task.id, unavailable: 1]}")
  end

  defp tag!(user, name, parent \\ nil) do
    {:ok, tag} =
      Tags.create_tag(user, %{"name" => name, "parent_id" => parent && parent.id}, command())

    tag
  end

  defp task!(user, title, opts \\ []) do
    attrs = %{
      "title" => title,
      "inbox" => Keyword.get(opts, :inbox, false),
      "project_id" => opts[:project_id]
    }

    {:ok, task} = Tasks.create_task(user, attrs, command())

    for tag <- Keyword.get(opts, :tags, []),
        do: {:ok, _} = Tags.tag_task(user, task.id, tag.id, command())

    task
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
