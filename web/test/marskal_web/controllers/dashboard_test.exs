defmodule MarskalWeb.DashboardTest do
  use MarskalWeb.ConnCase, async: true

  import Marskal.AccountsFixtures

  test "a normal user cannot open the dashboard", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/dev/dashboard")
    assert redirected_to(conn) == ~p"/open"
  end

  test "a superuser can open the dashboard", %{conn: conn} do
    user =
      user_fixture()
      |> Ecto.Changeset.change(superuser: true)
      |> Marskal.Repo.update!()

    conn = conn |> log_in_user(user) |> get(~p"/dev/dashboard")
    assert conn.status in [200, 302]
    if conn.status == 302, do: assert(redirected_to(conn) =~ "/dev/dashboard")
  end
end
