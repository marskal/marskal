defmodule MarskalWeb.Parsers.Multipart do
  @moduledoc """
  Multipart parser with a larger body limit only for `POST /imports`.

  Every other request keeps Plug's 8MB default.
  """

  @behaviour Plug.Parsers

  @multipart Plug.Parsers.MULTIPART
  @default_bytes 8_000_000
  @import_bytes 52_428_800

  @impl true
  def init(opts), do: opts

  @impl true
  def parse(conn, "multipart", subtype, headers, opts) do
    opts = @multipart.init([length: length_for(conn)] ++ opts)
    @multipart.parse(conn, "multipart", subtype, headers, opts)
  end

  def parse(conn, _type, _subtype, _headers, _opts), do: {:next, conn}

  def length_for(%{method: "POST", request_path: "/imports"}), do: @import_bytes
  def length_for(_conn), do: @default_bytes
end
