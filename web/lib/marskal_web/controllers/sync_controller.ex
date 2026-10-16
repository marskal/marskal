defmodule MarskalWeb.SyncController do
  @moduledoc "The sync API of ADR 0019, for clients signed in with OAuth."

  use MarskalWeb, :controller

  import MarskalWeb.APIAuth, only: [require_scope: 2]

  alias Marskal.Sync
  alias Marskal.Sync.Push

  plug :require_scope, "sync:read" when action in [:pull, :events]
  plug :require_scope, "sync:write" when action == :push

  def pull(conn, params) do
    case cursor(params["cursor"]) do
      {:ok, cursor} -> json(conn, Sync.pull(conn.assigns.current_scope.user, cursor))
      :error -> conn |> put_status(400) |> json(%{error: "invalid_request"})
    end
  end

  def push(conn, %{"commands" => commands}) when is_list(commands) do
    if length(commands) > Push.max_commands() do
      conn |> put_status(413) |> json(%{error: "too_many_commands", max: Push.max_commands()})
    else
      json(conn, %{results: Push.push(conn.assigns.current_scope.user, commands)})
    end
  end

  def push(conn, _params), do: conn |> put_status(400) |> json(%{error: "invalid_request"})

  @doc "Server-Sent Events saying when to pull (ADR 0030)."
  def events(conn, _params) do
    ["Bearer " <> token] = get_req_header(conn, "authorization")
    MarskalWeb.SyncEvents.stream(conn, String.trim(token))
  end

  defp cursor(nil), do: {:ok, nil}

  defp cursor(value) do
    case Integer.parse(value) do
      {cursor, ""} when cursor >= 0 -> {:ok, cursor}
      _ -> :error
    end
  end
end
