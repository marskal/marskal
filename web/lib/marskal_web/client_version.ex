defmodule MarskalWeb.ClientVersion do
  @moduledoc """
  The oldest client release the sync API serves (ADR 0040). A client names
  itself in `Marskal-Client: <client id>/<version>`; one older than its
  minimum gets `426` with `client_outdated`, before authentication.

  Every answer names the server's version in `Marskal-Server`.

  A request without the header passes: it comes from a client released
  before ADR 0040, which could not tell its user about a `426` anyway.
  """

  import Plug.Conn

  @doc """
  The minimum for a client without an override. Raise it when a server
  change breaks clients; a client that skipped the releases up to it needs
  an override (ADR 0038).
  """
  def default_minimum, do: "0.1.0"

  # Minimums for one client each, by OAuth client id (ADR 0021), such as
  # `"marskal-thunderbird" => "0.3.0"`.
  @overrides %{}

  @doc "Minimums for one client each, by OAuth client id."
  def overrides, do: @overrides

  @doc """
  The clients the server knows, by OAuth client id, and the `CHANGELOG.md`
  component each ships as.
  """
  def clients do
    %{
      "marskal-terminal" => "Terminal",
      "marskal-ios" => "iOS",
      "marskal-browser-extension" => "Browser extension",
      "marskal-thunderbird" => "Thunderbird extension"
    }
  end

  @doc "The minimum version for `client`."
  def minimum(client) do
    case Enum.find(@overrides, fn {id, _} -> id == client end) do
      {_, minimum} -> minimum
      nil -> default_minimum()
    end
  end

  @doc """
  `{client, version}` from a `Marskal-Client` value, or `:error` when it is
  not one.
  """
  def parse(value) do
    with [client, version] when client != "" <- String.split(String.trim(value), "/", parts: 2),
         {:ok, version} <- Version.parse(version) do
      {client, version}
    else
      _ -> :error
    end
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_resp_header(conn, "marskal-server", server_version())

    with [value] <- get_req_header(conn, "marskal-client"),
         {client, version} <- parse(value),
         minimum = minimum(client),
         :lt <- Version.compare(version, minimum) do
      outdated(conn, client, minimum)
    else
      _ -> conn
    end
  end

  defp outdated(conn, client, minimum) do
    body = %{
      error: "client_outdated",
      client: client,
      minimum_version: minimum,
      message: "This server needs #{client} #{minimum} or later."
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(426, Jason.encode!(body))
    |> halt()
  end

  defp server_version, do: to_string(Application.spec(:marskal, :vsn))
end
