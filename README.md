# Marskal Tasks

Personal soft-GTD task manager (recurring tasks, planning, nested tasks).  
See **[AGENTS.md](AGENTS.md)** and **[docs/adr/](docs/adr/)** for product rules.

## Stack

- Ruby on Rails **8.1** (Gemfile)
- PostgreSQL (devenv service locally)
- Hotwire (Turbo / Stimulus)

## Local development

```bash
# Enter environment (Ruby, Bundler, libpq, Postgres tooling)
devenv shell

# Install/update app gems (includes Rails — not from nixpkgs)
bundle install

# First time / after schema changes
bin/rails db:prepare

# Start Postgres + Rails together
devenv up          # foreground (logs)
# or: devenv up -d # background; devenv down to stop

# Rails only (Postgres already running): bin/dev
```

Open **http://marskal.localhost:8275** — sign up at `/registration/new`.  
Port **8275** ≈ TASK on a phone keypad. `*.localhost` → loopback (no `/etc/hosts`).

**Rails comes only from the Gemfile** (`bundle install` → `bin/rails`).  
devenv does **not** install `rubyPackages.rails`.

## Phases

| Phase | Focus |
|-------|--------|
| 0 | Foundation + auth (current) |
| 1 | Capture & clarify (inbox / lists / states) |
| 2 | Projects, folders, outliner, dates, tags |
| 3 | Recurrence |
| 4 | Review & polish |
