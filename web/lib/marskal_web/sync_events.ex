defmodule MarskalWeb.SyncEvents do
  @moduledoc """
  The sync event stream (ADR 0030): Server-Sent Events telling an open
  client that the user's data changed, so it pulls (ADR 0019). An event
  carries only the cursor of the latest change, as its id and its data; the
  rows still come by pull.

      id: 4269
      event: changed
      data: {"cursor":4269}

  On connect the stream sends the current cursor, unless `Last-Event-ID`
  already has it. A burst of writes, such as an import, is one event. A
  comment every `keep_alive` milliseconds keeps proxies from closing a quiet
  connection, and shows a dead one. Every `recheck` milliseconds the token
  is introspected again: a token that has expired, or a device signed out,
  ends the stream, and the client reconnects with a fresh token or not at
  all.
  """

  import Ecto.Query
  import Plug.Conn

  alias Marskal.Changes
  alias Marskal.Changes.Change
  alias Marskal.Repo

  @defaults [keep_alive: 25_000, recheck: 300_000, coalesce: 250, retry: 5_000]

  @doc "Streams events on `conn` until the client leaves or the token lapses."
  def stream(conn, token) do
    opts = Keyword.merge(@defaults, Application.get_env(:marskal, __MODULE__, []))
    user = conn.assigns.current_scope.user
    :ok = Changes.subscribe(user)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      # nginx passes the events on at once instead of buffering them.
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    state = %{
      user: user,
      token: token,
      opts: opts,
      sent: last_event_id(conn),
      flush: nil
    }

    with {:ok, conn} <- chunk(conn, "retry: #{opts[:retry]}\n\n"),
         {:ok, conn, state} <- send_cursor(conn, state) do
      Process.send_after(self(), :keep_alive, opts[:keep_alive])
      Process.send_after(self(), :recheck, opts[:recheck])
      loop(conn, state)
    else
      _ -> conn
    end
  end

  defp loop(conn, state) do
    receive do
      # Wait a moment for the rest of a burst, then send one event.
      {:marskal_change, _type, _id} when is_nil(state.flush) ->
        ref = Process.send_after(self(), :flush, state.opts[:coalesce])
        loop(conn, %{state | flush: ref})

      {:marskal_change, _type, _id} ->
        loop(conn, state)

      :flush ->
        case send_cursor(conn, %{state | flush: nil}) do
          {:ok, conn, state} -> loop(conn, state)
          _ -> conn
        end

      :keep_alive ->
        case chunk(conn, ": keep-alive\n\n") do
          {:ok, conn} ->
            Process.send_after(self(), :keep_alive, state.opts[:keep_alive])
            loop(conn, state)

          _ ->
            conn
        end

      :recheck ->
        case Marskal.Devices.authenticate(state.token) do
          {:ok, _user, _device, _scopes} ->
            Process.send_after(self(), :recheck, state.opts[:recheck])
            loop(conn, state)

          :error ->
            conn
        end

      :stop ->
        conn
    end
  end

  defp send_cursor(conn, state) do
    cursor = latest_cursor(state.user)

    if cursor > state.sent do
      event = "id: #{cursor}\nevent: changed\ndata: #{Jason.encode!(%{cursor: cursor})}\n\n"

      with {:ok, conn} <- chunk(conn, event), do: {:ok, conn, %{state | sent: cursor}}
    else
      {:ok, conn, state}
    end
  end

  defp latest_cursor(user) do
    Change
    |> where([c], c.user_id == ^user.id)
    |> select([c], max(c.id))
    |> Repo.one() || 0
  end

  # The cursor the client already has; -1 sends the current one regardless.
  defp last_event_id(conn) do
    with [value] <- get_req_header(conn, "last-event-id"),
         {cursor, ""} when cursor >= 0 <- Integer.parse(String.trim(value)) do
      cursor
    else
      _ -> -1
    end
  end
end
