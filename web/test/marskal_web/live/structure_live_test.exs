defmodule MarskalWeb.StructureLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  test "a new folder shows in the sidebar and accepts a project", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    {:ok, view, _html} = live(conn, ~p"/open")
    view |> element("button[aria-label='New folder']") |> render_click()

    assert {:error, {:live_redirect, %{to: path}}} =
             view
             |> form("#new-root-folder", project_folder: %{name: "Work"})
             |> render_submit()

    {:ok, folder_view, html} = live(conn, path)
    assert html =~ "Work"

    folder_view
    |> form("#new-project", project: %{title: "Launch website"})
    |> render_submit()

    assert render(folder_view) =~ "Launch website"
  end

  test "a folder's page is an outline of what it holds, rooted at the folder", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    command = fn -> Ecto.UUID.generate(version: 7) end

    {:ok, work} = Marskal.ProjectFolders.create_folder(user, %{"name" => "Work"}, command.())

    {:ok, client} =
      Marskal.ProjectFolders.create_folder(
        user,
        %{"name" => "Client", "parent_id" => work.id},
        command.()
      )

    {:ok, launch} =
      Marskal.Projects.create_project(
        user,
        %{"title" => "Launch", "project_folder_id" => work.id},
        command.()
      )

    {:ok, view, _html} = live(conn, ~p"/folders/#{work.id}")

    assert has_element?(view, "#folder-contents[data-root-id='#{work.id}']")
    assert has_element?(view, "#folder-contents-folder-#{client.id}[data-depth='0']")
    assert has_element?(view, "#folder-contents-project-#{launch.id}[data-depth='0']")

    render_hook(view, "nav-indent", %{"type" => "project", "id" => launch.id})
    assert has_element?(view, "#folder-contents-project-#{launch.id}[data-depth='1']")
    assert Marskal.Projects.get_project(user, launch.id).project_folder_id == client.id
  end

  test "a tag's page lists the tags inside it as an outline", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    command = fn -> Ecto.UUID.generate(version: 7) end

    {:ok, home} = Marskal.Tags.create_tag(user, %{"name" => "Home"}, command.())

    {:ok, garden} =
      Marskal.Tags.create_tag(user, %{"name" => "Garden", "parent_id" => home.id}, command.())

    {:ok, kitchen} =
      Marskal.Tags.create_tag(user, %{"name" => "Kitchen", "parent_id" => home.id}, command.())

    {:ok, view, _html} = live(conn, ~p"/tags/#{home.id}")

    assert has_element?(view, "#tag-children[data-root-id='#{home.id}']")
    assert has_element?(view, "#tag-children-tag-#{garden.id}[data-depth='0']")

    render_hook(view, "nav-indent", %{"type" => "tag", "id" => kitchen.id})
    assert has_element?(view, "#tag-children-tag-#{kitchen.id}[data-depth='1']")
    assert Marskal.Tags.get_tag(user, kitchen.id).parent_id == garden.id
  end
end
