defmodule Marskal.Uuid do
  @moduledoc """
  Name-based UUIDs (version 5, RFC 9562) for ids that every client must mint
  alike, such as tag link rows (ADR 0005) and rule-created occurrences
  (ADR 0014).
  """

  @doc "The v5 UUID of `name` in the `namespace` UUID, as a lowercase string."
  def v5(namespace, name) when is_binary(name) do
    ns = Ecto.UUID.dump!(namespace)
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> = :crypto.hash(:sha, ns <> name)
    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end
end
