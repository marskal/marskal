defmodule MarskalWeb.SyncController do
  @moduledoc "The sync API of ADR 0019, for clients signed in with OAuth."

  use MarskalWeb, :controller

  import MarskalWeb.APIAuth, only: [require_scope: 2]

  alias Marskal.Sync

  plug :require_scope, "sync:read" when action == :pull

  def pull(conn, params) do
    case cursor(params["cursor"]) do
      {:ok, cursor} -> json(conn, Sync.pull(conn.assigns.current_scope.user, cursor))
      :error -> conn |> put_status(400) |> json(%{error: "invalid_request"})
    end
  end

  defp cursor(nil), do: {:ok, nil}

  defp cursor(value) do
    case Integer.parse(value) do
      {cursor, ""} when cursor >= 0 -> {:ok, cursor}
      _ -> :error
    end
  end
end
