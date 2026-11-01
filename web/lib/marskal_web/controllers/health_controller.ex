defmodule MarskalWeb.HealthController do
  @moduledoc """
  `GET /up` for an uptime monitor, and for the `devenv up` ready probe.

  Postgres has to answer `SELECT 1`. The body is `ok` or `unavailable`, and
  the failure stays in the log. Those words are the monitor's contract.
  """

  use MarskalWeb, :controller

  require Logger

  # Inside the devenv ready probe (2s) and a monitor's request, so a stuck
  # database fails the check instead of holding the connection.
  @timeout 1_000

  def show(conn, _params) do
    {status, body} =
      case database() do
        :ok -> {200, "ok"}
        :error -> {503, "unavailable"}
      end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end

  defp database do
    case Marskal.Repo.query("SELECT 1", [], timeout: @timeout, pool_timeout: @timeout) do
      {:ok, _} -> :ok
      {:error, reason} -> failed(reason)
    end
  rescue
    error -> failed(error)
  end

  defp failed(reason) do
    Logger.warning("Health check failed: #{reason_message(reason)}")
    :error
  end

  defp reason_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp reason_message(reason), do: inspect(reason, limit: 5, printable_limit: 200)
end
