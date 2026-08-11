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

# Postgres (if not already up)
devenv up -d   # or: devenv processes up

# DB
bin/rails db:prepare

# App (http://marskal.localhost:8275 — port 8275 ≈ TASK on a phone keypad)
bin/dev
# or: bin/rails server
```

Open **http://marskal.localhost:8275** — sign up at `/registration/new`.  
`*.localhost` resolves to loopback on modern OSes; no `/etc/hosts` entry needed.

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
