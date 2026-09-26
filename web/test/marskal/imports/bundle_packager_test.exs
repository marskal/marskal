defmodule Marskal.Imports.BundlePackagerTest do
  use ExUnit.Case, async: true

  alias Marskal.Imports.BundlePackager
  alias Marskal.Imports.OmnifocusAdapter

  test "zips package members so the OmniFocus adapter can parse them" do
    {:ok, files} = :zip.unzip(OmnifocusBackup.tutorial_backup(), [:memory])

    entries =
      for {name, data} <- files,
          name = to_string(name),
          not String.ends_with?(name, "/") do
        {name, data}
      end

    packed = BundlePackager.call(entries)
    graph = OmnifocusAdapter.parse(packed, filename: "OmniFocus.ofocus-backup.zip")

    assert "Get to know OmniFocus 4 for Mac" in Enum.map(graph.projects, & &1.title)
    assert "Gør noget" in Enum.map(graph.tasks, & &1.title)
  end

  test "rejects zip-slip paths" do
    assert_raise ArgumentError, fn ->
      BundlePackager.call([{"../evil.txt", "nope"}])
    end
  end
end
