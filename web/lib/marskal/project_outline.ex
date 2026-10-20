defmodule Marskal.ProjectOutline do
  @moduledoc """
  Where folders and projects sit (ADR 0009). The subfolders and projects
  of one folder, or those at the top, are one sibling list, ordered by a
  rank drawn from both tables (ADR 0014). A folder can hold folders and
  projects; a project holds neither.

  An item is `{:folder, id}` or `{:project, id}`. The keyboard moves work
  on what the sidebar shows (`Marskal.ProjectNav`), so a dropped folder or
  a done project is not a neighbor to swap with or indent under. Each rank
  is still worked out against every live sibling, so it never lands on a
  hidden one's.
  """

  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.ProjectFolders
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.ProjectNav
  alias Marskal.Projects
  alias Marskal.Projects.Project
  alias Marskal.Rank
  alias Marskal.Repo

  @doc """
  Gives a new folder or project, or one moved to another folder without a
  rank, the last rank there. `parent_field` names the field that holds its
  folder.
  """
  def put_rank(%Ecto.Changeset{valid?: false} = changeset, _parent_field), do: changeset

  def put_rank(changeset, parent_field) do
    new? = Ecto.get_meta(changeset.data, :state) == :built

    if Ecto.Changeset.changed?(changeset, :rank) or
         not (new? or Ecto.Changeset.changed?(changeset, parent_field)) do
      changeset
    else
      user_id = Ecto.Changeset.get_field(changeset, :user_id)
      folder_id = Ecto.Changeset.get_field(changeset, parent_field)
      except = item(changeset.data)
      Ecto.Changeset.put_change(changeset, :rank, last_rank(user_id, folder_id, except))
    end
  end

  @doc """
  The rank for an item placed in `folder_id` (`nil` for the top): right
  after the sibling `sibling`, first for `nil`, or last for `:last`.
  `except` is the item being placed, left out of its own neighbors.
  """
  def rank_after(user_id, folder_id, sibling, except \\ nil)

  def rank_after(user_id, folder_id, :last, except),
    do: {:ok, last_rank(user_id, folder_id, except)}

  def rank_after(user_id, folder_id, nil, except) do
    first = user_id |> siblings(folder_id, except) |> List.first()
    {:ok, Rank.between(nil, first && first.rank)}
  end

  def rank_after(user_id, folder_id, sibling, except) do
    siblings = siblings(user_id, folder_id, except)

    case Enum.find(siblings, &(&1.item == sibling)) do
      nil ->
        {:error, :not_a_sibling}

      %{rank: rank} ->
        next = Enum.find(siblings, &(&1.rank > rank))
        {:ok, Rank.between(rank, next && next.rank)}
    end
  end

  @doc """
  Puts a folder or project in `folder_id` (`nil` for the top), right after
  the sibling `sibling` (`nil` for first, `:last` for last). A folder's
  subfolders and projects come along.
  """
  def place(%User{} = user, {:folder, id}, folder_id, sibling, command_id) do
    with {:ok, rank} <- rank_after(user.id, folder_id, sibling, {:folder, id}) do
      ProjectFolders.update_folder(user, id, %{parent_id: folder_id, rank: rank}, command_id)
    end
  end

  def place(%User{} = user, {:project, id}, folder_id, sibling, command_id) do
    with {:ok, rank} <- rank_after(user.id, folder_id, sibling, {:project, id}) do
      Projects.update_project(
        user,
        id,
        %{project_folder_id: folder_id, rank: rank},
        command_id
      )
    end
  end

  @doc "Files the item last in the folder just above it. A project above takes nothing."
  def indent(%User{} = user, item, command_id) do
    with {:ok, nav, parent_id} <- locate(user, item) do
      case neighbors(nav, parent_id, item) do
        {nil, _next} -> {:error, :first}
        {{:project, _id}, _next} -> {:error, :not_a_folder}
        {above, _next} -> place(user, item, elem(above, 1), :last, command_id)
      end
    end
  end

  @doc "Moves the item out of its folder, to just after it."
  def outdent(%User{} = user, item, command_id) do
    with {:ok, nav, parent_id} <- locate(user, item) do
      case parent_id && ProjectNav.folder(nav, parent_id) do
        nil -> {:error, :top_level}
        folder -> place(user, item, folder.parent_id, {:folder, folder.id}, command_id)
      end
    end
  end

  @doc "Swaps the item with the sibling above it."
  def move_up(%User{} = user, item, command_id) do
    with {:ok, nav, parent_id} <- locate(user, item) do
      case neighbors(nav, parent_id, item) do
        {nil, _next} ->
          {:error, :first}

        {above, _next} ->
          {before, _} = neighbors(nav, parent_id, above)
          place(user, item, parent_id, before, command_id)
      end
    end
  end

  @doc "Swaps the item with the sibling below it."
  def move_down(%User{} = user, item, command_id) do
    with {:ok, nav, parent_id} <- locate(user, item) do
      case neighbors(nav, parent_id, item) do
        {_above, nil} -> {:error, :last}
        {_above, below} -> place(user, item, parent_id, below, command_id)
      end
    end
  end

  # The item's folder, as the sidebar shows it.
  defp locate(user, item) do
    nav = ProjectNav.build(user)

    case ProjectNav.parent_id(nav, item) do
      {:ok, parent_id} -> {:ok, nav, parent_id}
      :error -> {:error, :not_found}
    end
  end

  # The visible siblings just above and below the item.
  defp neighbors(nav, parent_id, item) do
    items = nav |> ProjectNav.children(parent_id) |> Enum.map(&ProjectNav.item/1)
    index = Enum.find_index(items, &(&1 == item))
    above = if index > 0, do: Enum.at(items, index - 1)
    {above, Enum.at(items, index + 1)}
  end

  defp last_rank(user_id, folder_id, except) do
    last = user_id |> siblings(folder_id, except) |> List.last()
    Rank.between(last && last.rank, nil)
  end

  # Every live folder and project in the folder, in order.
  defp siblings(user_id, folder_id, except) do
    folders =
      ProjectFolder
      |> where([f], f.user_id == ^user_id and is_nil(f.discarded_at))
      |> where_parent(:parent_id, folder_id)
      |> select([f], %{id: f.id, rank: f.rank})

    projects =
      Project
      |> where([p], p.user_id == ^user_id and is_nil(p.discarded_at))
      |> where_parent(:project_folder_id, folder_id)
      |> select([p], %{id: p.id, rank: p.rank})

    (Enum.map(Repo.all(folders), &Map.put(&1, :item, {:folder, &1.id})) ++
       Enum.map(Repo.all(projects), &Map.put(&1, :item, {:project, &1.id})))
    |> Enum.reject(&(&1.item == except))
    |> Enum.sort_by(&{&1.rank, &1.id})
  end

  defp where_parent(query, field, nil), do: where(query, [r], is_nil(field(r, ^field)))
  defp where_parent(query, field, id), do: where(query, [r], field(r, ^field) == ^id)

  defp item(%ProjectFolder{id: id}) when not is_nil(id), do: {:folder, id}
  defp item(%Project{id: id}) when not is_nil(id), do: {:project, id}
  defp item(_record), do: nil
end
