defmodule Marskal.Repo.Migrations.ConfirmExistingUsers do
  use Ecto.Migration

  # Accounts made before confirmation existed were never asked to confirm.
  # Unconfirmed ones would now be locked out, and then deleted. Magic link
  # tokens are no longer read.
  def up do
    execute "UPDATE users SET confirmed_at = inserted_at WHERE confirmed_at IS NULL"
    execute "DELETE FROM users_tokens WHERE context = 'login'"
  end

  def down, do: :ok
end
