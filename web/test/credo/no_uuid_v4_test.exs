unless Code.ensure_loaded?(Marskal.Credo.NoUuidV4) do
  Code.require_file("../../credo/checks/no_uuid_v4.ex", __DIR__)
end

defmodule Marskal.Credo.NoUuidV4Test do
  use Credo.Test.Case

  alias Marskal.Credo.NoUuidV4

  setup_all do
    {:ok, _} = Application.ensure_all_started(:credo)
    :ok
  end

  test "flags Ecto.UUID.generate without version 7" do
    """
    defmodule Sample do
      def a, do: Ecto.UUID.generate()
      def b, do: Ecto.UUID.generate(version: 4)
      def c, do: Ecto.UUID.bingenerate()
      def d(opts), do: Ecto.UUID.generate(opts)
    end
    """
    |> to_source_file()
    |> run_check(NoUuidV4)
    |> assert_issues(fn issues -> assert [_, _, _, _] = issues end)
  end

  test "flags an aliased Ecto.UUID too" do
    """
    defmodule Sample do
      alias Ecto.UUID
      def a, do: UUID.generate()
    end
    """
    |> to_source_file()
    |> run_check(NoUuidV4)
    |> assert_issue()
  end

  test "allows version 7 and other Ecto.UUID functions" do
    """
    defmodule Sample do
      def a, do: Ecto.UUID.generate(version: 7)
      def b, do: Ecto.UUID.generate(version: 7, precision: :monotonic)
      def c(id), do: Ecto.UUID.cast(id)
      def d, do: Marskal.Uuid.v5("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "x")
    end
    """
    |> to_source_file()
    |> run_check(NoUuidV4)
    |> refute_issues()
  end

  test "flags autogenerate: true on a UUID key or field" do
    """
    defmodule Sample do
      use Ecto.Schema
      @primary_key {:id, Ecto.UUID, autogenerate: true}
      schema "samples" do
        field :token, :binary_id, autogenerate: true
        field :count, :integer
      end
    end
    """
    |> to_source_file()
    |> run_check(NoUuidV4)
    |> assert_issues(fn issues -> assert [_, _] = issues end)
  end

  test "allows autogenerate with version 7 or off" do
    """
    defmodule Sample do
      use Ecto.Schema
      @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
      schema "samples" do
        field :other, Ecto.UUID, autogenerate: false
      end
    end
    """
    |> to_source_file()
    |> run_check(NoUuidV4)
    |> refute_issues()
  end

  test "flags gen_random_uuid() in SQL" do
    ~S'''
    defmodule Sample.Migration do
      use Ecto.Migration

      def change do
        execute "ALTER TABLE things ALTER COLUMN id SET DEFAULT gen_random_uuid()"

        execute """
        CREATE TABLE others (id uuid PRIMARY KEY DEFAULT gen_random_uuid())
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(NoUuidV4)
    |> assert_issues(fn issues -> assert [_, _] = issues end)
  end

  test "allows uuidv7() in SQL" do
    ~S'''
    defmodule Sample.Migration do
      use Ecto.Migration
      def change, do: execute("CREATE TABLE t (id uuid PRIMARY KEY DEFAULT uuidv7())")
    end
    '''
    |> to_source_file()
    |> run_check(NoUuidV4)
    |> refute_issues()
  end
end
