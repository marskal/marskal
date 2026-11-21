defmodule Marskal.Accents do
  @moduledoc """
  The accent palette: a fixed set of colors for telling things apart.

  CSS owns how each one looks (`--palette-*` in `app.css`). These names
  are the choices. A user's badge takes one, and a project or folder may
  later be marked with one. `pick/1` hashes the id, so the same record
  always wears the same color, and the choice does not follow a name
  that two people share or that someone later edits.

  The order of `names/0` is the hash's buckets. Appending a name gives
  some ids a new color; reordering does too.
  """

  # Wheel order. Amber is the logo's hue, teal the brand's; see app.css.
  @names ~w(red amber lime teal blue indigo violet pink)

  def names, do: @names

  @doc """
  The accent name for `id`.

  FNV-1a, 32-bit, over the id's bytes, so the pick stays put when Erlang
  does not. `"a"` is the published test vector (`0xE40C292C`).

      iex> Marskal.Accents.pick("a")
      "blue"
      iex> Marskal.Accents.pick("018f6b2e-7c3a-7000-8000-000000000001")
      "teal"
      iex> Marskal.Accents.pick("018f6b2e-7c3a-7000-8000-000000000002")
      "violet"
  """
  def pick(id) when is_binary(id) do
    Enum.at(@names, rem(fnv1a32(id), length(@names)))
  end

  # Offset basis 2166136261, prime 16777619, masked to 32 bits each byte.
  defp fnv1a32(binary) do
    for <<byte <- binary>>, reduce: 2_166_136_261 do
      hash -> Bitwise.band(Bitwise.bxor(hash, byte) * 16_777_619, 0xFFFFFFFF)
    end
  end
end
