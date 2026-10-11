%{
  configs: [
    %{
      name: "default",
      plugins: [{ExSlop, []}],
      requires: ["credo/checks/*.ex"],
      checks: [
        {Credo.Check.Design.AliasUsage, false},
        {ExSlop.Check.Readability.NarratorDoc, false},
        # The check and its tests spell out what they ban.
        {Marskal.Credo.NoUuidV4, files: %{excluded: ["credo/checks/", "test/credo/"]}}
      ]
    }
  ]
}
