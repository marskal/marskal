defmodule MarskalWeb.ClientVersionTest do
  use MarskalWeb.ConnCase, async: true

  import Marskal.AccountsFixtures
  import Marskal.OAuthFixtures

  alias MarskalWeb.ClientVersion

  @changelog Path.expand("../../../CHANGELOG.md", __DIR__)

  setup %{conn: conn} do
    tokens = signed_in_device(user_fixture())
    %{authed: put_req_header(conn, "authorization", "Bearer " <> tokens.access_token)}
  end

  describe "the Marskal-Client header" do
    test "a client at its minimum or later is served", %{authed: authed} do
      minimum = ClientVersion.minimum("marskal-terminal")

      conn =
        authed
        |> put_req_header("marskal-client", "marskal-terminal/#{minimum}")
        |> get(~p"/api/v1/sync/pull")

      assert json_response(conn, 200)
      assert [_] = get_resp_header(conn, "marskal-server")
    end

    test "an older client is refused with the version it needs", %{conn: conn} do
      # Before authentication: no token needed to hear it.
      conn =
        conn
        |> put_req_header("marskal-client", "marskal-terminal/0.0.9")
        |> get(~p"/api/v1/sync/pull")

      minimum = ClientVersion.minimum("marskal-terminal")

      assert %{
               "error" => "client_outdated",
               "client" => "marskal-terminal",
               "minimum_version" => ^minimum,
               "message" => "This server needs marskal-terminal " <> _
             } = json_response(conn, 426)

      assert [_] = get_resp_header(conn, "marskal-server")
    end

    test "the event stream checks it too", %{authed: authed} do
      conn =
        authed
        |> put_req_header("marskal-client", "marskal-ios/0.0.1")
        |> get(~p"/api/v1/sync/events")

      assert json_response(conn, 426)["error"] == "client_outdated"
    end

    test "a client that sends none is served", %{authed: authed} do
      assert authed |> get(~p"/api/v1/sync/pull") |> json_response(200)
    end

    test "a value that does not parse counts as no header", %{authed: authed} do
      assert authed
             |> put_req_header("marskal-client", "marskal-terminal")
             |> get(~p"/api/v1/sync/pull")
             |> json_response(200)
    end
  end

  test "parse/1" do
    assert {"marskal-ios", version} = ClientVersion.parse("marskal-ios/0.3.0")
    assert to_string(version) == "0.3.0"
    assert {"marskal-ios", _} = ClientVersion.parse("marskal-ios/0.3.0-dev+abc")
    assert ClientVersion.parse("marskal-ios") == :error
    assert ClientVersion.parse("/0.3.0") == :error
    assert ClientVersion.parse("marskal-ios/three") == :error
  end

  test "an unknown client is held to the default" do
    assert ClientVersion.minimum("someone-else") == ClientVersion.default_minimum()
  end

  # ADR 0040: a minimum names a version that client shipped in, or its
  # users have nothing to update to.
  test "every client's minimum is a version it shipped" do
    shipped = last_release_per_component(File.read!(@changelog))

    for {client, component} <- ClientVersion.clients() do
      minimum = ClientVersion.minimum(client)
      last = Map.get(shipped, component)

      assert last, "#{component} has no release in CHANGELOG.md"

      assert Version.compare(last, minimum) != :lt,
             "#{client} needs #{minimum}, but #{component} last shipped in #{last}"
    end
  end

  test "overrides name known clients" do
    for client <- Map.keys(ClientVersion.overrides()) do
      assert Map.has_key?(ClientVersion.clients(), client)
    end
  end

  # `## 0.2.0 - date` opens a release, `### Component` a component in it.
  defp last_release_per_component(changelog) do
    changelog
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, fn
      "## " <> heading, {_, shipped} ->
        {heading |> String.split(" ") |> hd(), shipped}

      "### " <> component, {version, shipped} when version != nil ->
        {version,
         Map.update(shipped, String.trim(component), version, fn last ->
           if Version.compare(version, last) == :gt, do: version, else: last
         end)}

      _, acc ->
        acc
    end)
    |> elem(1)
  end
end
