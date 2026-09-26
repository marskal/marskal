# 0016. Elixir and Phoenix for the web app

## Status

Accepted

Supersedes the widget technology in [ADR 0012](0012-viewcomponent-scoped-css.md)
when `web/` is ported. The CSS rules in that ADR stay: no Tailwind, no UI kit,
tokens on `:root`, isolation with `@scope`.

Supersedes the auth *mechanism* in [ADR 0003](0003-rails-auth-and-sharing.md)
when `web/` is ported. Folder sharing, owner scope, and email + password
sessions stay.

Does not start the port. The tree in `web/` remains Rails until that work
replaces it.

## Context

The web app is the online client and the host for a later offline iOS app
([ADR 0014](0014-offline-sync.md), [ADR 0015](0015-repository-layout.md)).
Rails can grow an API beside the monolith. Phoenix contexts are the app, and
LiveView is one caller of them. That is the boundary the phone will use.

`mix phx.new` on Phoenix 1.8 turns on Tailwind and daisyUI, and
`phx.gen.auth` also generates magic-link login. Neither is a product decision.
There is no production data. The running Rails app is local only.

## Decision

### Stack

| Piece | Choice |
|-------|--------|
| Language | Elixir **1.20**, Erlang/OTP **29**. Pin both in `web/devenv.nix`. Do not float `pkgs.elixir`. |
| Web | Phoenix **1.8**, LiveView **1.2**, Bandit |
| App | One Mix app, OTP name `:marskal`, modules `Marskal` and `MarskalWeb`. Not an umbrella. |
| Data | Ecto and Postgrex, the existing Postgres 18 |
| Auth | `mix phx.gen.auth`, email + password, session cookie. Magic link stays unused. |
| Jobs | Oban, in the same database |
| Mail | Swoosh |
| UI | HEEx function components. esbuild only for LiveView's JavaScript |
| Icons | Lucide, as today |

Generate with `--no-tailwind`. Delete leftover daisyUI classes rather than
styling toward them. Phoenix's generated `AGENTS.md` is framework advice and
lives inside `web/`. Product rules stay at the repository root.

### Data types

- Domain primary keys are Postgres `uuid` with `DEFAULT uuidv7()`, and an
  explicit id is allowed ([ADR 0011](0011-uuidv7-primary-keys.md)). Do not use
  `Ecto.UUID` (that is v4) or `:binary_id`.
- The change-feed cursor is `bigint GENERATED ALWAYS AS IDENTITY`
  ([ADR 0014](0014-offline-sync.md)). Not a sequence, not a uuid.
- Migrations are Ecto. Enums, `uuidv7()` defaults, and identity columns are
  raw SQL in those migrations, not a portable type the migration layer invents.

### Write path

LiveViews call context functions (`create`, `rename`, `complete`, and the
rest). A LiveView does not build one changeset that writes the whole row back.
The same functions are what the sync endpoint will call later. A client may
supply the id. Postgres fills `uuidv7()` only when the insert omits it.

Recurrence stays a pure function of the rule plus the JSON fixtures
([ADR 0007](0007-recurrence.md), [ADR 0014](0014-offline-sync.md)). Oban runs
it. The calendar math does not live in a LiveView.

### Dev and deploy

At the port, `web/devenv.nix` drops Ruby and gains Elixir and Erlang. Postgres
18 and port **8275** stay. Production remains a VPS with Nix and env-based
secrets ([ADR 0004](0004-hosting-vps-nix.md)): `DATABASE_URL`,
`SECRET_KEY_BASE`. A `mix release` is the artifact. Do not adopt a PaaS as the
model.

### Not in the first port

The sync HTTP API, device tokens, Oban cron for regular recurrence, `mdex`
for CommonMark notes, and OTP `:zip` for OmniFocus backups. Lucide can be
wired when the first icon is needed, not as a pile of SVGs on day one.

## Consequences

- Do not add a second app directory beside `web/`. The port replaces `web/`.
  Until that replacement, the Rails rules in `AGENTS.md` are how the current
  tree is changed. Do not mix Elixir into it.
- New UI on the Phoenix app is a function component plus an `@scope`
  stylesheet. No Tailwind, no daisyUI, no ViewComponent.
- `phx.gen.auth` output is trimmed so the login that ships is email +
  password. Do not present magic link as the way in.
- Tests are ExUnit. LiveView tests cover the screens. Recurrence fixtures are
  the shared vectors, not a second implementation hidden in a test helper.
- ADR 0012's ViewComponent and ERB decisions apply only to the Rails tree.
  ADR 0003's `bin/rails generate authentication` line likewise. Sharing and
  the session model do not change.
