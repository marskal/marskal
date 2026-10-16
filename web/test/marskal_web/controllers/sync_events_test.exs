defmodule MarskalWeb.SyncEventsTest do
  use MarskalWeb.ConnCase, async: true

  import Marskal.AccountsFixtures
  import Marskal.OAuthFixtures

  alias Marskal.Repo
  alias Marskal.Tasks

  setup %{conn: conn} do
    user = user_fixture()
    tokens = signed_in_device(user)
    authed = put_req_header(conn, "authorization", "Bearer " <> tokens.access_token)
    %{user: user, authed: authed, device: tokens.device}
  end

  describe "GET /api/v1/sync/events" do
    test "starts with the current cursor", %{user: user, authed: authed} do
      {:ok, _} = Tasks.create_task(user, %{title: "Milk"}, Ecto.UUID.generate(version: 7))
      cursor = latest(user)

      {conn, body} = authed |> open(user) |> stop()

      assert get_resp_header(conn, "content-type") == ["text/event-stream; charset=utf-8"]
      assert get_resp_header(conn, "x-accel-buffering") == ["no"]
      assert body =~ "retry: 5000\n\n"
      assert events(body) == [cursor]
    end

    test "sends nothing on connect when Last-Event-ID has the cursor", %{
      user: user,
      authed: authed
    } do
      {:ok, _} = Tasks.create_task(user, %{title: "Milk"}, Ecto.UUID.generate(version: 7))

      {_conn, body} =
        authed
        |> put_req_header("last-event-id", Integer.to_string(latest(user)))
        |> open(user)
        |> stop()

      assert events(body) == []
    end

    test "a burst of writes is one event with the latest cursor", %{user: user, authed: authed} do
      stream = open(authed, user)

      for title <- ["One", "Two", "Three"] do
        {:ok, _} = Tasks.create_task(user, %{title: title}, Ecto.UUID.generate(version: 7))
      end

      Process.sleep(100)
      {_conn, body} = stop(stream)

      assert events(body) == [0, latest(user)]
    end

    test "another user's writes send nothing", %{user: user, authed: authed} do
      stream = open(authed, user)
      other = user_fixture()
      {:ok, _} = Tasks.create_task(other, %{title: "Not yours"}, Ecto.UUID.generate(version: 7))

      Process.sleep(100)
      {_conn, body} = stop(stream)

      assert events(body) == [0]
    end

    test "ends when the device is signed out", %{user: user, authed: authed, device: device} do
      stream = open(authed, user)
      Repo.delete!(device)

      conn = Task.await(stream.task, 2_000)
      assert conn.state == :chunked
    end

    test "needs a token with sync:read", %{conn: conn, user: user} do
      assert conn |> get(~p"/api/v1/sync/events") |> json_response(401)

      write_only = signed_in_device(user, %{"scope" => "sync:write"})

      assert conn
             |> put_req_header("authorization", "Bearer " <> write_only.access_token)
             |> get(~p"/api/v1/sync/events")
             |> json_response(403) == %{"error" => "insufficient_scope"}
    end
  end

  # Opens the stream in a task, and returns once it listens for changes.
  defp open(conn, user) do
    task = Task.async(fn -> get(conn, ~p"/api/v1/sync/events") end)
    wait_until(fn -> subscribed?(task.pid, user) end)
    %{task: task}
  end

  defp stop(%{task: task}) do
    send(task.pid, :stop)
    conn = Task.await(task)
    {conn, conn.resp_body}
  end

  defp subscribed?(pid, user) do
    Marskal.PubSub
    |> Registry.lookup("changes:user:#{user.id}")
    |> Enum.any?(fn {subscriber, _} -> subscriber == pid end)
  end

  defp wait_until(check, tries \\ 100) do
    cond do
      check.() -> :ok
      tries == 0 -> flunk("the stream never subscribed")
      true -> Process.sleep(10) && wait_until(check, tries - 1)
    end
  end

  # The cursors the stream sent, in order.
  defp events(body) do
    ~r/^id: (\d+)\nevent: changed\ndata: \{"cursor":(\d+)\}\n\n/m
    |> Regex.scan(body)
    |> Enum.map(fn [_, id, data] ->
      assert id == data
      String.to_integer(id)
    end)
  end

  defp latest(user) do
    import Ecto.Query

    Repo.one(from c in Marskal.Changes.Change, where: c.user_id == ^user.id, select: max(c.id)) ||
      0
  end
end
