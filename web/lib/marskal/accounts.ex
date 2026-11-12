defmodule Marskal.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Marskal.Repo

  alias Marskal.Accounts.{User, UserPreferences, UserToken}
  alias Marskal.Changes

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@marskal.example")
      %User{}

      iex> get_user_by_email("unknown@marskal.example")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@marskal.example", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@marskal.example", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}, opts \\ []) do
    opts = Keyword.merge([hash_password: false, validate_unique: false], opts)
    User.registration_changeset(user, attrs, opts)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Marskal.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user's name.
  """
  def change_user_name(%User{} = user, attrs \\ %{}) do
    User.name_changeset(user, attrs)
  end

  @doc """
  Sets what to call the user. A blank name clears it.
  """
  def update_user_name(%User{} = user, attrs) do
    user
    |> User.name_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Marskal.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.
  Every device signed in through Hydra is signed out too (ADR 0021).

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    with {:ok, {user, _expired}} = ok <-
           user
           |> User.password_changeset(attrs)
           |> update_user_and_delete_all_tokens() do
      Marskal.Devices.sign_out_all(user)
      ok
    end
  end

  ## Preferences

  @doc """
  The user's preferences (ADR 0023): the loaded ones, else read.
  """
  def preferences(%User{preferences: %UserPreferences{} = preferences}), do: preferences
  def preferences(%User{} = user), do: Repo.get_by!(UserPreferences, user_id: user.id)

  @doc "The zone the user's days are in."
  def timezone(%User{} = user), do: preferences(user).timezone

  @doc "The CLDR locale the user's dates and times are formatted in (ADR 0027)."
  def locale(%User{} = user), do: preferences(user).locale

  def change_preferences(%UserPreferences{} = preferences, attrs \\ %{}),
    do: UserPreferences.changeset(preferences, attrs)

  @doc """
  Patches the user's preferences, through the change feed. `id` is the
  row's, as a client knows it from a pull; nil is the user's own.
  """
  def update_preferences(%User{} = user, id \\ nil, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "user_preferences", fn ->
      case fetch_preferences(user, id) do
        nil -> {:error, :not_found}
        preferences -> Changes.commit(UserPreferences.changeset(preferences, attrs))
      end
    end)
  end

  defp fetch_preferences(user, nil), do: Repo.get_by(UserPreferences, user_id: user.id)
  defp fetch_preferences(user, id), do: Repo.get_owned(UserPreferences, user, id)

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    case Repo.one(query) do
      {user, inserted_at} -> {Repo.preload(user, :preferences), inserted_at}
      nil -> nil
    end
  end

  @doc """
  Makes the token for a change of email, for the link the web layer emails
  to the new address. `user` carries the new email; `current_email` is the
  one the account has now.
  """
  def build_update_email_token(%User{} = user, current_email) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")
    Repo.insert!(user_token)
    encoded_token
  end

  ## Confirmation

  @doc """
  Makes a confirmation token for an unconfirmed user, for the link the web
  layer emails. Returns `{:ok, encoded_token}`, or `{:error, :sent_recently}`
  when a link went out in the last minute.
  """
  def build_confirmation_token(%User{confirmed_at: nil} = user),
    do: build_email_token(user, "confirm")

  @doc "The unconfirmed user a confirmation token was sent to, or nil."
  def get_user_by_confirmation_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{confirmed_at: nil} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Confirms the account a confirmation token was sent to. The password must
  be the account's, so a link alone cannot confirm an account someone else
  registered with the address; the owner resets the password instead.

  Returns `{:ok, {user, expired_tokens}}`, `{:error, :not_found}` for a bad
  or expired token, or `{:error, :invalid_password}`.
  """
  def confirm_user(token, password) when is_binary(password) do
    case get_user_by_confirmation_token(token) do
      nil ->
        {:error, :not_found}

      user ->
        if User.valid_password?(user, password) do
          user
          |> User.confirm_changeset()
          |> update_user_and_delete_all_tokens()
        else
          {:error, :invalid_password}
        end
    end
  end

  @doc """
  Deletes accounts left unconfirmed longer than a confirmation link lasts,
  which frees their addresses. They never signed in, so nothing of theirs
  was synced.
  """
  def delete_unconfirmed_users(now \\ DateTime.utc_now(:second)) do
    cutoff = DateTime.add(now, -UserToken.confirm_validity_in_days(), :day)

    Repo.delete_all(from u in User, where: is_nil(u.confirmed_at) and u.inserted_at < ^cutoff)
  end

  ## Password reset

  @doc """
  Makes a password reset token, for the link the web layer emails. Returns
  `{:ok, encoded_token}`, or `{:error, :sent_recently}` when a link went out
  in the last minute.
  """
  def build_reset_password_token(%User{} = user), do: build_email_token(user, "reset_password")

  @doc "The user a password reset token was sent to, or nil."
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Sets a new password from a reset link. The link proves the address, so an
  unconfirmed account is confirmed too. Every session and token ends, and
  every device signed in through Hydra is signed out (ADR 0021).

  Returns `{:ok, {user, expired_tokens}}` or `{:error, changeset}`.
  """
  def reset_user_password(%User{} = user, attrs) do
    changeset = User.password_changeset(user, attrs)
    changeset = if user.confirmed_at, do: changeset, else: User.confirm_changeset(changeset)

    with {:ok, {user, _expired}} = ok <- update_user_and_delete_all_tokens(changeset) do
      Marskal.Devices.sign_out_all(user)
      ok
    end
  end

  defp build_email_token(user, context) do
    if Repo.exists?(UserToken.sent_recently_query(user, context, 1)) do
      {:error, :sent_recently}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, context)
      Repo.insert!(user_token)
      {:ok, encoded_token}
    end
  end

  @doc """
  Deletes tokens past their validity: sessions nobody logged out of, and
  links nobody followed.
  """
  def delete_expired_tokens(now \\ DateTime.utc_now(:second)) do
    Repo.delete_all(UserToken.expired_query(now))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
