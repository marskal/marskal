# Sample data for local development. Idempotent. Never required in production.
#
#   mix run priv/repo/seeds.exs
#
# Sign in as:
#   mts@marskal.example / H3mm3l1gh3d  — superuser, inbox and open tasks
#   kvp@marskal.example / H3mm3l1gh3d  — second user, one open task
#
# Folders, projects, and the tasks that belonged to them are not seeded.
# That graph comes back when those models are ported. The old list is in
# git history (`web/db/seeds.rb` before the Phoenix port).

password = "H3mm3l1gh3d"

defmodule Marskal.DevSeed do
  import Ecto.Query

  def user!(email, superuser, password) do
    case Marskal.Repo.get_by(Marskal.Accounts.User, email: email) do
      %Marskal.Accounts.User{} = user ->
        user

      nil ->
        %Marskal.Accounts.User{}
        |> Ecto.Changeset.change(%{
          email: email,
          hashed_password: Argon2.hash_pwd_salt(password),
          confirmed_at: DateTime.utc_now(:second),
          timezone: "Europe/Copenhagen",
          superuser: superuser
        })
        |> Marskal.Repo.insert!()
    end
  end

  def tasks!(user, rows) do
    already? =
      Marskal.Repo.exists?(
        from t in Marskal.Tasks.Task,
          where: t.user_id == ^user.id
      )

    unless already? do
      Enum.each(rows, fn row -> insert!(user, row) end)
    end
  end

  defp insert!(user, {title, notes, days_ago, placement}) do
    command = Ecto.UUID.generate()
    {:ok, task} = Marskal.Tasks.create_task(user, %{title: title, notes: notes}, command)

    task =
      case placement do
        :inbox ->
          task

        :open ->
          {:ok, task} = Marskal.Tasks.clarify_task(user, task.id, Ecto.UUID.generate())
          task

        :done ->
          {:ok, task} = Marskal.Tasks.clarify_task(user, task.id, Ecto.UUID.generate())
          {:ok, task} = Marskal.Tasks.complete_task(user, task.id, Ecto.UUID.generate())
          task

        :dropped ->
          {:ok, task} = Marskal.Tasks.drop_task(user, task.id, Ecto.UUID.generate())
          task
      end

    at = DateTime.utc_now(:second) |> DateTime.add(-days_ago * 86_400, :second)

    task
    |> Ecto.Changeset.change(%{inserted_at: at, updated_at: at})
    |> Marskal.Repo.update!()
  end
end

dev = Marskal.DevSeed.user!("mts@marskal.example", true, password)
other = Marskal.DevSeed.user!("kvp@marskal.example", false, password)

Marskal.DevSeed.tasks!(dev, [
  {"Buy milk", "From the corner shop.", 1, :inbox},
  {"Call the dentist", nil, 2, :inbox},
  {"Diagnose the weird car noise", "Only when turning left.", 3, :inbox},
  {"Review folder breadcrumbs against ADR 0009", nil, 5, :open},
  {"Sketch a weekly review checklist", nil, 7, :open},
  {"Finish Rails auth", nil, 45, :done},
  {"Evaluate a third note-taking app", nil, 50, :dropped}
])

Marskal.DevSeed.tasks!(other, [
  {"Secret task", nil, 16, :open}
])

IO.puts("Sample accounts (password: #{password}):")
IO.puts("  #{dev.email}  — superuser")
IO.puts("  #{other.email} — second user")
