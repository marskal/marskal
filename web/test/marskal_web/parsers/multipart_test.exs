defmodule MarskalWeb.Parsers.MultipartTest do
  use ExUnit.Case, async: true

  test "a body over 8MB is refused except on the import upload" do
    body = multipart_body(8_100_000)

    assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      parse(body, "/users/log-in")
    end

    conn = parse(body, "/imports")
    assert byte_size(conn.body_params["pad"]) == 8_100_000
  end

  test "the import limit is only for POST /imports" do
    assert MarskalWeb.Parsers.Multipart.length_for(%{method: "POST", request_path: "/imports"}) ==
             52_428_800

    assert MarskalWeb.Parsers.Multipart.length_for(%{method: "POST", request_path: "/inbox"}) ==
             8_000_000

    assert MarskalWeb.Parsers.Multipart.length_for(%{method: "GET", request_path: "/imports"}) ==
             8_000_000
  end

  defp parse(body, path) do
    opts =
      Plug.Parsers.init(
        parsers: [:urlencoded, MarskalWeb.Parsers.Multipart, :json],
        pass: ["*/*"],
        json_decoder: Jason
      )

    :post
    |> Plug.Test.conn(path, body)
    |> Plug.Conn.put_req_header("content-type", "multipart/form-data; boundary=----b")
    |> Plug.Parsers.call(opts)
  end

  defp multipart_body(size) do
    "------b\r\nContent-Disposition: form-data; name=\"pad\"\r\n\r\n" <>
      String.duplicate("a", size) <>
      "\r\n------b--\r\n"
  end
end
