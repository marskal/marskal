defmodule Marskal.OAuthFixtures do
  @moduledoc """
  A stand-in for Hydra's admin API (ADR 0021), and devices signed in
  through it. Test access tokens are `test_at|user id|device id|scopes`;
  the stub introspects them as live. Every admin call is also sent to the
  test process as `{:hydra, method, path, params}`, with the JSON or form
  body under `"body"`.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  alias Marskal.Devices

  @default_scope "offline_access sync:read sync:write"

  @doc """
  Installs the stub. `responses` maps `{method, path}` to a JSON body or
  `{status, body}`; anything else answers as Hydra would for a happy path.
  """
  def stub_hydra(responses \\ %{}) do
    test = self()

    Req.Test.stub(Marskal.Hydra, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = decode(raw)
      params = Map.put(conn.query_params, "body", body)
      send(test, {:hydra, conn.method, conn.request_path, params})

      case Map.get(responses, {conn.method, conn.request_path}) do
        nil -> default(conn, body)
        {status, reply} -> reply(conn, status, reply)
        reply -> reply(conn, 200, reply)
      end
    end)
  end

  @doc "A device of `user` and a live access token for it."
  def signed_in_device(user, attrs \\ %{}) do
    stub_hydra()
    scope = attrs["scope"] || @default_scope

    {:ok, device} =
      Devices.create(user, %{
        name: attrs["name"] || "marskal on laptop",
        client_id: "marskal-terminal",
        consent_request_id: Ecto.UUID.generate()
      })

    %{
      access_token: Enum.join(["test_at", user.id, device.id, scope], "|"),
      scope: scope,
      device: device
    }
  end

  defp default(conn, body) do
    case {conn.method, conn.request_path} do
      {"POST", "/admin/oauth2/introspect"} ->
        reply(conn, 200, introspect(body["token"]))

      {"DELETE", _} ->
        Plug.Conn.send_resp(conn, 204, "")

      {"PUT", "/admin/oauth2/auth/requests/" <> _} ->
        reply(conn, 200, %{redirect_to: "http://hydra.test/next"})

      other ->
        flunk("unexpected Hydra call #{inspect(other)}")
    end
  end

  defp introspect("test_at|" <> rest) do
    [user_id, device_id, scope] = String.split(rest, "|")

    %{
      active: true,
      token_use: "access_token",
      sub: user_id,
      client_id: "marskal-terminal",
      scope: scope,
      ext: %{device_id: device_id}
    }
  end

  defp introspect(_token), do: %{active: false}

  defp reply(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp decode(""), do: %{}

  defp decode(raw) do
    case Jason.decode(raw) do
      {:ok, json} -> json
      {:error, _} -> URI.decode_query(raw)
    end
  end
end
