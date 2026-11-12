defmodule Marskal.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Marskal.Dates
  alias Marskal.ReviewInterval

  @states [:to_do, :done, :dropped]
  @review [:review_interval, :next_review_on, :last_reviewed_at]

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "projects" do
    field :title, :string
    field :notes, :string
    field :url, :string
    field :flagged, :boolean, default: false
    field :rank, :string
    field :state, Ecto.Enum, values: @states, default: :to_do
    field :defer_until, :utc_datetime
    field :deferred_indefinitely, :boolean, default: false
    field :planned_at, :utc_datetime
    field :due_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :discarded_at, :utc_datetime
    field :occurrence_for, :utc_datetime
    # When the project is next due for review, as a day on the user's clock,
    # and how far apart its reviews are. Both are nil for Never (ADR 0026).
    field :review_interval, Marskal.ReviewInterval
    field :next_review_on, :date
    field :last_reviewed_at, :utc_datetime

    belongs_to :user, Marskal.Accounts.User
    belongs_to :project_folder, Marskal.ProjectFolders.ProjectFolder
    belongs_to :series, Marskal.Recurrence.Series

    timestamps(type: :utc_datetime)
  end

  @doc """
  The fields a client may write, by op (ADR 0019). Any other field rejects
  the command. A patch of `discarded_at` is a delete.
  """
  def client_fields(:insert),
    do:
      ~w(title notes url flagged project_folder_id state defer_until deferred_indefinitely planned_at due_at series_id occurrence_for review_interval next_review_on last_reviewed_at)

  def client_fields(:patch),
    do:
      ~w(title notes url flagged project_folder_id state defer_until deferred_indefinitely planned_at due_at series_id occurrence_for review_interval next_review_on last_reviewed_at discarded_at)

  @doc """
  A new project. `generated: true` is for the occurrences
  `Marskal.Recurrence` creates.
  """
  def create_changeset(project, user, attrs, opts \\ []) do
    project
    |> cast(attrs, [
      :id,
      :title,
      :notes,
      :url,
      :flagged,
      :project_folder_id,
      :state,
      :series_id,
      :occurrence_for,
      :rank,
      :resolved_at | Dates.fields() ++ @review
    ])
    |> validate_required([:title, :flagged])
    |> validate_length(:title, max: Marskal.Tasks.Task.title_max())
    |> validate_length(:notes, max: Marskal.Tasks.Task.notes_max())
    |> Marskal.Url.validate("projects")
    |> put_change(:user_id, user.id)
    |> Dates.put_defer()
    |> Dates.put_resolved_at(opts[:at])
    |> put_review(user)
    |> owned_folder_constraint()
    |> validate_live_folder()
    |> Marskal.ProjectOutline.put_rank(:project_folder_id)
    |> date_constraints()
    |> review_constraints()
    |> Marskal.Recurrence.validate_occurrence(user.id, :project, generated: opts[:generated])
  end

  @doc """
  Any subset of the editable fields. Only fields that differ reach the
  patch. `series_id` and `occurrence_for` join a series, once. A move to
  another folder without a rank goes last there; clients do not write the
  rank (`client_fields/1`).
  """
  def update_changeset(project, attrs, opts \\ []) do
    project
    |> cast(attrs, [
      :title,
      :notes,
      :url,
      :flagged,
      :project_folder_id,
      :state,
      :series_id,
      :occurrence_for,
      :rank | Dates.fields() ++ @review
    ])
    |> validate_required([:title, :state, :flagged])
    |> validate_length(:title, max: Marskal.Tasks.Task.title_max())
    |> validate_length(:notes, max: Marskal.Tasks.Task.notes_max())
    |> Marskal.Url.validate("projects")
    |> Dates.put_defer()
    |> Dates.put_resolved_at(opts[:at])
    |> put_review_interval(project, opts[:timezone])
    |> owned_folder_constraint()
    |> validate_live_folder()
    |> Marskal.ProjectOutline.put_rank(:project_folder_id)
    |> date_constraints()
    |> review_constraints()
    |> Marskal.Recurrence.validate_occurrence(project.user_id, :project)
  end

  def discard_changeset(project), do: Dates.discard(project)

  # A new project takes the user's default interval unless it names one, as
  # a series takes week_start, and is first due that interval after today
  # (ADR 0026).
  defp put_review(changeset, user) do
    changeset = ReviewInterval.validate(changeset, :review_interval)
    preferences = Marskal.Accounts.preferences(user)

    interval =
      if Map.has_key?(changeset.params, "review_interval"),
        do: get_field(changeset, :review_interval),
        else: preferences.default_review_interval

    changeset
    |> put_change(:review_interval, interval)
    |> put_next_review_on(interval, fn -> Dates.today(preferences.timezone) end)
  end

  # A new interval counts from the last review, or from the day the project
  # was made. A day that has passed leaves the project due now.
  defp put_review_interval(changeset, project, zone) do
    changeset = ReviewInterval.validate(changeset, :review_interval)

    case fetch_change(changeset, :review_interval) do
      {:ok, interval} ->
        put_next_review_on(changeset, interval, fn ->
          (project.last_reviewed_at || project.inserted_at)
          |> DateTime.shift_zone!(zone || raise(ArgumentError, "needs the user's timezone"))
          |> DateTime.to_date()
        end)

      :error ->
        changeset
    end
  end

  # A next review day the command names is kept; the database refuses one
  # without an interval.
  defp put_next_review_on(changeset, interval, from) do
    cond do
      Map.has_key?(changeset.params, "next_review_on") ->
        changeset

      is_nil(interval) ->
        put_change(changeset, :next_review_on, nil)

      ReviewInterval.valid?(interval) ->
        put_change(changeset, :next_review_on, ReviewInterval.next_on(from.(), interval))

      true ->
        changeset
    end
  end

  defp review_constraints(changeset) do
    changeset
    |> check_constraint(:review_interval,
      name: :projects_review_interval,
      message: "must be whole days, weeks, months, or years"
    )
    |> check_constraint(:next_review_on,
      name: :projects_next_review_on,
      message: "must be set exactly when the project is reviewed"
    )
  end

  # A discarded folder takes no projects. Another user's folder fails the
  # foreign key below.
  defp validate_live_folder(changeset) do
    validate_change(changeset, :project_folder_id, fn :project_folder_id, id ->
      case Marskal.Repo.get(Marskal.ProjectFolders.ProjectFolder, id) do
        %{discarded_at: %DateTime{}} -> [project_folder_id: "must belong to you"]
        _ -> []
      end
    end)
  end

  # projects_project_folder_id_fkey is (project_folder_id, user_id).
  defp owned_folder_constraint(changeset) do
    foreign_key_constraint(changeset, :project_folder_id,
      name: :projects_project_folder_id_fkey,
      message: "must belong to you"
    )
  end

  defp date_constraints(changeset) do
    changeset
    |> check_constraint(:defer_until,
      name: :projects_defer_one_shape,
      message: "cannot be set when deferred indefinitely"
    )
    |> check_constraint(:resolved_at, name: :projects_resolved_at_set, message: "is required")
  end
end
