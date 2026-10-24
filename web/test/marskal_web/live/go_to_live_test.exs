defmodule MarskalWeb.GoToLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.Projects
  alias Marskal.Tags

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "opens on the views and narrows as the user types", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{"title" => "Garden shed"}, command())
    {:ok, tag} = Tags.create_tag(user, %{"name" => "Garden"}, command())
    {:ok, view, _html} = live(conn, ~p"/open")

    assert has_element?(view, "header [data-go-to]")
    view |> element("#go-to") |> render_hook("open", %{})
    assert has_element?(view, "#go-to-view-inbox a[href='/inbox']")

    view |> form("#go-to-form", %{query: "gard"}) |> render_change()

    refute has_element?(view, "#go-to-view-inbox")
    assert has_element?(view, "#go-to-tag-#{tag.id} a[data-opens-inspector]", "Garden")

    assert has_element?(
             view,
             "#go-to-project-#{project.id} a[href='/projects/#{project.id}?project=#{project.id}']"
           )

    view |> form("#go-to-form", %{query: "zzz"}) |> render_change()
    assert has_element?(view, "#go-to .empty")
  end

  test "a done project says so", %{conn: conn, user: user} do
    {:ok, project} = Projects.create_project(user, %{"title" => "Old launch"}, command())
    {:ok, _} = Projects.update_project(user, project.id, %{"state" => "done"}, command())
    {:ok, view, _html} = live(conn, ~p"/open")

    view |> element("#go-to") |> render_hook("open", %{})
    view |> form("#go-to-form", %{query: "launch"}) |> render_change()

    assert has_element?(view, "#go-to-project-#{project.id}.is-hidden .state", "Done")
  end

  defp command, do: Ecto.UUID.generate(version: 7)
end
