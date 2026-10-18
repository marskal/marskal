defmodule MarskalWeb.SidebarTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Tags

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "folders and tags with something inside get a toggle for that list", %{
    conn: conn,
    user: user
  } do
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())
    {:ok, empty} = ProjectFolders.create_folder(user, %{"name" => "Empty"}, command())

    {:ok, project} =
      Projects.create_project(
        user,
        %{"title" => "Launch", "project_folder_id" => work.id},
        command()
      )

    {:ok, home} = Tags.create_tag(user, %{"name" => "Home"}, command())

    {:ok, garden} =
      Tags.create_tag(user, %{"name" => "Garden", "parent_id" => home.id}, command())

    {:ok, view, _html} = live(conn, ~p"/open")

    assert has_element?(
             view,
             "#sidebar-projects-folder-#{work.id}[data-depth='0'] .nav-toggle[aria-expanded='true']"
           )

    assert has_element?(view, "#sidebar-projects-project-#{project.id}[data-depth='1']", "Launch")
    refute has_element?(view, "#sidebar-projects-folder-#{empty.id} .nav-toggle")
    refute has_element?(view, "#sidebar-projects-project-#{project.id}[data-container]")

    assert has_element?(view, "#sidebar-tags-tag-#{home.id} .nav-toggle")
    assert has_element?(view, "#sidebar-tags-tag-#{garden.id}[data-depth='1']", "Garden")
    refute has_element?(view, "#sidebar-tags-tag-#{garden.id} .nav-toggle")
  end

  test "the views and every row are stops for the keys", %{conn: conn, user: user} do
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())
    {:ok, view, _html} = live(conn, ~p"/open")

    assert has_element?(view, "#sidebar .sidebar-links a[data-nav-stop]", "Inbox")
    assert has_element?(view, "#sidebar-projects-folder-#{work.id} a[data-nav-stop]")
    assert has_element?(view, "#sidebar a[data-nav-stop]", "Untagged")
  end

  test "rows move by drop and by the outline keys", %{conn: conn, user: user} do
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())
    {:ok, launch} = Projects.create_project(user, %{"title" => "Launch"}, command())
    {:ok, home} = Tags.create_tag(user, %{"name" => "Home"}, command())
    {:ok, garden} = Tags.create_tag(user, %{"name" => "Garden"}, command())

    {:ok, view, _html} = live(conn, ~p"/open")

    render_hook(view, "nav-indent", %{"type" => "project", "id" => launch.id})
    assert Projects.get_project(user, launch.id).project_folder_id == work.id
    assert has_element?(view, "#sidebar-projects-project-#{launch.id}[data-depth='1']")

    render_hook(view, "nav-outdent", %{"type" => "project", "id" => launch.id})
    assert Projects.get_project(user, launch.id).project_folder_id == nil

    render_hook(view, "nav-up", %{"type" => "project", "id" => launch.id})
    assert view |> element("#sidebar-projects > li:first-child") |> render() =~ "Launch"

    render_hook(view, "nav-place", %{
      "type" => "tag",
      "id" => garden.id,
      "parent_id" => home.id,
      "after_type" => nil,
      "after_id" => nil
    })

    assert Tags.get_tag(user, garden.id).parent_id == home.id
    assert has_element?(view, "#sidebar-tags-tag-#{garden.id}[data-depth='1']")

    render_hook(view, "nav-place", %{
      "type" => "folder",
      "id" => work.id,
      "parent_id" => nil,
      "after_type" => "project",
      "after_id" => launch.id
    })

    assert view |> element("#sidebar-projects > li:first-child") |> render() =~ "Launch"
  end

  test "a project never takes anything inside it", %{conn: conn, user: user} do
    {:ok, launch} = Projects.create_project(user, %{"title" => "Launch"}, command())
    {:ok, report} = Projects.create_project(user, %{"title" => "Report"}, command())

    {:ok, view, _html} = live(conn, ~p"/open")

    render_hook(view, "nav-indent", %{"type" => "project", "id" => report.id})
    assert Projects.get_project(user, report.id).project_folder_id == nil

    html =
      render_hook(view, "nav-place", %{
        "type" => "project",
        "id" => report.id,
        "parent_id" => launch.id,
        "after_type" => nil,
        "after_id" => nil
      })

    assert html =~ "Could not move that there."
    assert Projects.get_project(user, report.id).project_folder_id == nil
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
