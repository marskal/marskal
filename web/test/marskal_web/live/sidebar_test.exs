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

    {:ok, _project} =
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
             "#sidebar .nav-toggle[aria-controls='sidebar-folder-#{work.id}'][aria-expanded='true']"
           )

    assert has_element?(view, "#sidebar-folder-#{work.id}", "Launch")
    refute has_element?(view, "#sidebar .nav-toggle[aria-controls='sidebar-folder-#{empty.id}']")

    assert has_element?(view, "#sidebar .nav-toggle[aria-controls='sidebar-tag-#{home.id}']")
    assert has_element?(view, "#sidebar-tag-#{home.id}", "Garden")
    refute has_element?(view, "#sidebar .nav-toggle[aria-controls='sidebar-tag-#{garden.id}']")
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
