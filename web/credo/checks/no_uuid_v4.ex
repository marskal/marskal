defmodule Marskal.Credo.NoUuidV4 do
  @moduledoc false

  use Credo.Check,
    id: "MSK001",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Generated UUIDs are version 7 (ADR 0011). Version 4 is random, so it
      scatters inserts into a B-tree index, such as the primary keys and the
      unique index on changes.command_id.

      This check flags the ways v4 gets in:

      * `Ecto.UUID.generate/1`, `bingenerate/1`, or `autogenerate/1` without a
        literal `version: 7`; with no options Ecto makes v4.
      * An `Ecto.UUID` or `:binary_id` field or primary key with
        `autogenerate: true`, which also makes v4.
      * `gen_random_uuid()` in SQL. Use the `uuidv7()` default instead.

      Write `Ecto.UUID.generate(version: 7)`, or leave the id to the database.
      UUIDv5 ids made with `Marskal.Uuid.v5/2` are fine.
      """
    ]

  @generators [:generate, :bingenerate, :autogenerate]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    result = Credo.Code.prewalk(source_file, &walk/2, ctx)
    Enum.uniq_by(result.issues, &{&1.line_no, &1.trigger})
  end

  # Ecto.UUID.generate() and friends, or UUID.generate() after an alias.
  defp walk({{:., _, [{:__aliases__, meta, aliases}, fun]}, _, args} = ast, ctx)
       when fun in @generators and aliases in [[:Ecto, :UUID], [:UUID]] do
    if v7?(args) do
      {ast, ctx}
    else
      trigger = Enum.map_join(aliases, ".", &Atom.to_string/1) <> ".#{fun}"
      {ast, put_issue(ctx, issue(ctx, meta, trigger, "Generate UUIDs with `version: 7`."))}
    end
  end

  # @primary_key {:id, Ecto.UUID, autogenerate: true}
  defp walk({:{}, meta, [_name, type, opts]} = ast, ctx) do
    {ast, autogenerate_issue(ctx, meta, type, opts)}
  end

  # field :id, Ecto.UUID, autogenerate: true
  defp walk({:field, meta, [_name, type, opts]} = ast, ctx) do
    {ast, autogenerate_issue(ctx, meta, type, opts)}
  end

  # A string, heredoc, or sigil that calls gen_random_uuid().
  defp walk({_, meta, args} = ast, ctx) when is_list(meta) and is_list(args) do
    if Enum.any?(args, &calls_gen_random_uuid?/1) do
      message = "Use the `uuidv7()` default, not `gen_random_uuid()`."
      {ast, put_issue(ctx, issue(ctx, meta, "gen_random_uuid", message))}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp v7?([opts]) when is_list(opts), do: Keyword.keyword?(opts) and opts[:version] == 7
  defp v7?(_args), do: false

  defp autogenerate_issue(ctx, meta, type, opts) do
    if uuid_type?(type) and Keyword.keyword?(opts) and opts[:autogenerate] == true do
      message = "`autogenerate: true` makes UUIDv4; use `autogenerate: [version: 7]`."
      put_issue(ctx, issue(ctx, meta, "autogenerate", message))
    else
      ctx
    end
  end

  defp uuid_type?({:__aliases__, _, aliases}), do: aliases in [[:Ecto, :UUID], [:UUID]]
  defp uuid_type?(type), do: type == :binary_id

  defp calls_gen_random_uuid?(text) when is_binary(text), do: text =~ "gen_random_uuid"

  defp calls_gen_random_uuid?({:<<>>, _, parts}) when is_list(parts),
    do: Enum.any?(parts, &calls_gen_random_uuid?/1)

  defp calls_gen_random_uuid?(_ast), do: false

  defp issue(ctx, meta, trigger, message) do
    format_issue(ctx, message: message, trigger: trigger, line_no: meta[:line])
  end
end
