defmodule Marskal.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Marskal.Accounts` context.
  """

  import Ecto.Query

  alias Marskal.Accounts
  alias Marskal.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@marskal.example"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    email = email_from(attrs) || unique_user_email()

    {:ok, user} =
      %Accounts.User{}
      |> Accounts.User.email_changeset(%{email: email})
      |> Marskal.Repo.insert()

    user
  end

  defp email_from(%{email: email}) when is_binary(email), do: email
  defp email_from(%{"email" => email}) when is_binary(email), do: email
  defp email_from(_attrs), do: nil

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    user
    |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
    |> Marskal.Repo.update!()
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Marskal.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  @doc "An account registered with the valid password but not confirmed."
  def registered_user_fixture(attrs \\ %{}) do
    {:ok, user} = Accounts.register_user(valid_user_attributes(attrs))
    user
  end

  @doc "A confirmed user with the valid password."
  def password_user_fixture(attrs \\ %{}), do: attrs |> user_fixture() |> set_password()

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Marskal.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
