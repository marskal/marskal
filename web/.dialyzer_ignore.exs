# OTP 29 makes :sets.set/0 opaque. MapSet is a struct around that set and is
# not itself opaque, so Dialyzer warns on ordinary MapSet and Ecto.Multi use.
[
  {"lib/marskal/imports.ex", :call_without_opaque},
  {"lib/marskal/imports/applier.ex", :call_without_opaque},
  {"lib/marskal/imports/applier.ex", :call_with_opaque},
  {"lib/marskal/imports/omnifocus_adapter.ex", :call_without_opaque},
  {"lib/marskal/imports/omnifocus_adapter.ex", :call_with_opaque},
  {"lib/marskal/imports/todoist_adapter.ex", :call_without_opaque},
  {"lib/marskal/imports/todoist_adapter.ex", :call_with_opaque}
]
