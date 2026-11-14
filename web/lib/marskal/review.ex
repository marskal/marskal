defmodule Marskal.Review do
  @moduledoc """
  The projects due for review (ADR 0026).

  A project is due while it is To-Do, live, and its next review day is on
  or before today in the user's zone. Deferred projects are listed, the
  indefinite ones too, and so are projects in a Dropped folder: the review
  is where the user decides about them.
  """

  import Ecto.Query

  alias Marskal.Accounts
  alias Marskal.Accounts.User
  alias Marskal.Dates
  alias Marskal.ProjectNav
  alias Marskal.Projects.Project
  alias Marskal.Repo
  alias Marskal.Tags
  alias Marskal.Tasks

  defmodule Row do
    @moduledoc "A project due for review, with what the list shows beside it."
    defstruct [:project, :folder, deferred?: false, stalled?: false]
  end

  @doc """
  The projects due, by next review day, then in sidebar order, each as a
  `Row`. A project is stalled when it is not deferred and has no available
  task (ADR 0008).
  """
  def due(%User{} = user) do
    now = DateTime.utc_now()
    nav = ProjectNav.build(user, [:dropped, :deferred])
    order = nav |> ProjectNav.project_ids() |> Enum.with_index() |> Map.new()

    user
    |> due_query()
    |> Repo.all()
    |> Enum.sort_by(&{Date.to_gregorian_days(&1.next_review_on), Map.get(order, &1.id, 0)})
    |> Enum.map(fn project ->
      deferred? = Dates.deferred?(project, now)

      %Row{
        project: project,
        folder: project.project_folder_id && ProjectNav.folder(nav, project.project_folder_id),
        deferred?: deferred?,
        stalled?: not deferred? and not available_task?(user, project)
      }
    end)
  end

  @doc "How many projects are due."
  def count(%User{} = user), do: user |> due_query() |> Repo.aggregate(:count)

  @doc "The first project due other than `id`, or nil."
  def next(%User{} = user, id) do
    user |> due() |> Enum.find(&(&1.project.id != id)) |> then(&(&1 && &1.project))
  end

  @doc "Whether the project is due for review today."
  def due?(%User{} = user, %Project{} = project) do
    project.state == :to_do and is_nil(project.discarded_at) and
      project.next_review_on != nil and
      Date.compare(project.next_review_on, today(user)) != :gt
  end

  defp due_query(user) do
    today = today(user)

    Project
    |> where([p], p.user_id == ^user.id and p.state == :to_do and is_nil(p.discarded_at))
    |> where([p], p.next_review_on <= ^today)
  end

  defp today(user), do: user |> Accounts.timezone() |> Dates.today()

  defp available_task?(user, project) do
    user
    |> Tasks.list_project_tasks(project.id)
    |> then(&Tags.reject_unavailable(user, &1))
    |> Enum.any?()
  end
end
