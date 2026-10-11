defmodule MarskalWeb.StructureLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  test "a new folder shows in the sidebar and accepts a project", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    {:ok, view, _html} = live(conn, ~p"/")
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
end
