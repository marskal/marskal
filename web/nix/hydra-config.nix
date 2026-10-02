/**
  Ory Hydra's settings for a host (ADR 0021): what nix/module.nix runs,
  apart from the database and the secret, which come from the environment.
*/
{
  host,
  publicPort,
  adminPort,
}:
{
  serve = {
    public = {
      host = "127.0.0.1";
      port = publicPort;
    };
    admin = {
      host = "127.0.0.1";
      port = adminPort;
    };
  };
  urls = {
    self = {
      issuer = "https://${host}";
      public = "https://${host}";
    };
    login = "https://${host}/oauth/login";
    consent = "https://${host}/oauth/consent";
    logout = "https://${host}/users/log-out";
    error = "https://${host}/oauth/error";
    device = {
      verification = "https://${host}/device";
      success = "https://${host}/device/done";
    };
  };
  strategies.access_token = "opaque";
  ttl = {
    access_token = "1h";
    refresh_token = "2160h";
    device_user_code = "10m";
  };
  oauth2 = {
    # The command line and a terminal UI share one grant (ADR 0020).
    grant.refresh_token.rotation_grace_period = "30s";
    device_authorization = {
      token_polling_interval = "5s";
      user_code.entropy_preset = "medium";
    };
  };
}
