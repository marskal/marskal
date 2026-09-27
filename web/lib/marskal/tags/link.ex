defmodule Marskal.Tags.Link do
  @moduledoc """
  Link-row helpers shared by `TaskTag` and `ProjectTag` (ADR 0005).

  A link's id is the v5 UUID of its pair, so every device tagging the same
  task with the same tag names the same row. Untagging sets `discarded_at`;
  tagging again clears it.
  """

  # A made-up constant fixed by ADR 0005 ("0005" is the ADR number). Every
  # client hashes with it, so changing it would rename every link row and
  # duplicate links across devices.
  @namespace "a5c0ffee-0005-5000-8000-000000000005"

  @doc "The link id for `kind` (`:task` or `:project`), owner id, and tag id."
  def id(kind, owner_id, tag_id) when kind in [:task, :project] do
    Marskal.Uuid.v5(@namespace, "#{kind}|#{String.downcase(owner_id)}|#{String.downcase(tag_id)}")
  end
end
