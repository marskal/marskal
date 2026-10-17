defmodule MarskalWeb.UserNotifier do
  @moduledoc """
  Emails sent for account changes. They live in the web layer because
  their text goes through Gettext (ADR 0028); `Marskal.Accounts` makes the
  tokens they link to.
  """

  use Gettext, backend: MarskalWeb.Gettext
  use MarskalWeb, :verified_routes

  import Swoosh.Email

  alias Marskal.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:marskal, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc "The link that finishes a registration."
  def deliver_confirmation_instructions(user, token) do
    deliver(
      user.email,
      gettext("Confirm your Marskal account"),
      gettext(
        """
        Hi %{email},

        Open this link to confirm your Marskal account. You'll be asked for the password you chose:

        %{url}

        The link works for 7 days. If you didn't create an account, ignore this email and the account is deleted when the link expires.
        """,
        email: user.email,
        url: url(~p"/users/confirm/#{token}")
      )
    )
  end

  @doc "The link that sets a new password."
  def deliver_reset_password_instructions(user, token) do
    deliver(
      user.email,
      gettext("Reset your Marskal password"),
      gettext(
        """
        Hi %{email},

        Open this link to choose a new password for your Marskal account:

        %{url}

        The link works for an hour. If you didn't ask for this, ignore this email; your password stays as it is.
        """,
        email: user.email,
        url: url(~p"/users/reset-password/#{token}")
      )
    )
  end

  @doc "The link, sent to the new address, that completes a change of email."
  def deliver_update_email_instructions(user, token) do
    deliver(
      user.email,
      gettext("Confirm your new email address"),
      gettext(
        """
        Hi %{email},

        Open this link to make this the email address of your Marskal account:

        %{url}

        If you didn't ask for this change, ignore this email.
        """,
        email: user.email,
        url: url(~p"/users/settings/confirm-email/#{token}")
      )
    )
  end
end
