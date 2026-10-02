defmodule MarskalWeb.SyncControllerTest do
  use MarskalWeb.ConnCase, async: true

  import Marskal.AccountsFixtures
  import Marskal.OAuthFixtures

  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    tokens = signed_in_device(user)
    authed = put_req_header(conn, "authorization", "Bearer " <> tokens.access_token)
    %{user: user, authed: authed}
  end

  describe "GET /api/v1/sync/pull" do
    test "a snapshot, then the changes after its cursor", %{user: user, authed: authed} do
      {:ok, task} = Tasks.create_task(user, %{title: "Milk"}, Ecto.UUID.generate())

      snapshot = authed |> get(~p"/api/v1/sync/pull") |> json_response(200)
      assert snapshot["snapshot"]
      assert [%{"id" => id, "title" => "Milk"}] = snapshot["rows"]["task"]
      assert id == task.id

      {:ok, _} = Tasks.complete_task(user, task.id, Ecto.UUID.generate())

      changes =
        authed
        |> get(~p"/api/v1/sync/pull?#{[cursor: snapshot["cursor"]]}")
        |> json_response(200)

      refute changes["snapshot"]
      assert [%{"state" => "done"}] = changes["rows"]["task"]
      assert changes["gone"] == []
    end

    test "a cursor that is not a whole number is refused", %{authed: authed} do
      assert authed |> get(~p"/api/v1/sync/pull?cursor=-1") |> json_response(400) ==
               %{"error" => "invalid_request"}

      assert authed |> get(~p"/api/v1/sync/pull?cursor=abc") |> json_response(400)
    end

    test "needs a token with sync:read", %{conn: conn, user: user} do
      assert conn |> get(~p"/api/v1/sync/pull") |> json_response(401)

      write_only = signed_in_device(user, %{"scope" => "sync:write"})

      assert conn
             |> put_req_header("authorization", "Bearer " <> write_only.access_token)
             |> get(~p"/api/v1/sync/pull")
             |> json_response(403) == %{"error" => "insufficient_scope"}
    end
  end
end
