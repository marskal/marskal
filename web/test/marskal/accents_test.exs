defmodule Marskal.AccentsTest do
  use ExUnit.Case, async: true

  alias Marskal.Accents

  doctest Accents

  test "every name is a palette token the badge can select" do
    css =
      :marskal
      |> :code.priv_dir()
      |> Path.join("static/assets/css/app.css")
      |> File.read!()

    for name <- Accents.names() do
      assert css =~ "--palette-#{name}:"
      assert css =~ ~s([data-accent="#{name}"])
    end

    assert css =~ "--palette-ink:"
  end

  test "the published FNV-1a vector lands on blue" do
    # 0xE40C292C is FNV-1a 32 of "a", and that bucket is blue.
    assert Accents.pick("a") == "blue"
  end

  test "the same id keeps its color, and the id is what decides" do
    assert Accents.pick("018f6b2e-7c3a-7000-8000-000000000001") == "teal"
    assert Accents.pick("018f6b2e-7c3a-7000-8000-000000000001") == "teal"
    assert Accents.pick("018f6b2e-7c3a-7000-8000-000000000002") == "violet"
  end

  test "the eight names all occur" do
    picked =
      MapSet.new(1..400, fn n ->
        Accents.pick("user-#{n}")
      end)

    assert picked == MapSet.new(Accents.names())
  end
end
