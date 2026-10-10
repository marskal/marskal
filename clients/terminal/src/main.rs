//! `marskal`: Marskal tasks from the terminal (ADR 0020).
//!
//! Writes go to the local outbox first and work offline. A write then
//! syncs; a read syncs first when the last sync is over a minute old. A
//! network failure there is not an error: the command works on local rows
//! and says it did not sync. `--json` prints a stable shape for scripts
//! and agents.

mod api;
mod auth;
mod config;
mod error;
mod output;
mod paths;
mod state;
mod sync;

use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Args, Parser, Subcommand};
use jiff::Timestamp;
use jiff::tz::TimeZone;
use marskal_sync::dates::{self, DateField};
use marskal_sync::{Location, NewProject, NewTask, Store, TaskFilter, TaskPatch, TaskState};
use uuid::Uuid;

use crate::api::Api;
use crate::auth::TokenStore;
use crate::config::{Config, default_server, normalize_server};
use crate::error::{CliError, Result};
use crate::output::Output;
use crate::state::State;

const STALE_AFTER_SECONDS: i64 = 60;

#[derive(Parser)]
#[command(name = "marskal", version, about = "Marskal tasks from the terminal")]
struct Cli {
    /// Print JSON, in a stable shape, for scripts and agents.
    #[arg(long, global = true)]
    json: bool,

    /// Do not touch the network.
    #[arg(long, global = true)]
    offline: bool,

    /// The server, overriding the config file.
    #[arg(long, global = true, env = "MARSKAL_SERVER")]
    server: Option<String>,

    /// The local database file, overriding the default under $XDG_DATA_HOME.
    #[arg(long, global = true, env = "MARSKAL_DB")]
    db: Option<PathBuf>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Sign this device in, through the browser.
    Login {
        /// Allow reading only.
        #[arg(long)]
        read_only: bool,
        /// Print the link without opening a browser.
        #[arg(long)]
        no_browser: bool,
    },
    /// Sign this device out.
    Logout {
        /// Also delete the local database, unsent edits included.
        #[arg(long)]
        forget: bool,
    },
    /// Send local edits and fetch the server's.
    Sync,
    /// Show sign-in and sync state.
    Status,
    /// Capture a task. Without a place it goes to the inbox.
    Add(AddArgs),
    /// List tasks: the open stream by default.
    Ls(LsArgs),
    /// Show one task.
    Show { task: String },
    /// Mark tasks Done.
    Done { tasks: Vec<String> },
    /// Mark tasks Dropped: you will not do them.
    Drop { tasks: Vec<String> },
    /// Mark tasks To-Do again.
    Reopen { tasks: Vec<String> },
    /// Change a task's title, notes, URL, flag, or dates.
    Edit(EditArgs),
    /// Open a task's URL with the system's opener: files too.
    Open { task: String },
    /// Move a task: to the inbox, out of every project, or into one.
    Move {
        task: String,
        #[command(flatten)]
        to: PlaceArgs,
    },
    /// Delete tasks and their subtasks. Done and Drop are how work ends.
    Rm { tasks: Vec<String> },
    /// Tag a task.
    Tag { task: String, tag: String },
    /// Take a tag off a task.
    Untag { task: String, tag: String },
    /// List projects, or add one.
    Projects {
        #[command(subcommand)]
        action: Option<ProjectAction>,
    },
    /// List tags, or add one.
    Tags {
        #[command(subcommand)]
        action: Option<TagAction>,
    },
    /// Show commands the server refused.
    Rejections,
}

#[derive(Subcommand)]
enum ProjectAction {
    /// Add a project.
    Add {
        title: Vec<String>,
        /// The folder to file it in.
        #[arg(long)]
        folder: Option<String>,
        /// A page, file, or ticket: https://…, file:///…
        #[arg(long, short)]
        url: Option<String>,
        /// Flag it, which flags its tasks.
        #[arg(long, short)]
        flag: bool,
    },
    /// Flag a project, which flags its tasks.
    Flag { project: String },
    /// Clear a project's flag.
    Unflag { project: String },
    /// Mark a project Done.
    Done { project: String },
    /// Mark a project Dropped.
    Drop { project: String },
    /// Mark a project To-Do again.
    Reopen { project: String },
}

#[derive(Subcommand)]
enum TagAction {
    /// Add a tag.
    Add {
        name: String,
        /// The tag to put it under.
        #[arg(long)]
        parent: Option<String>,
    },
}

#[derive(Args)]
#[group(multiple = false)]
struct PlaceArgs {
    /// Into a project, by id, id prefix, or title.
    #[arg(long, short)]
    project: Option<String>,
    /// Into the inbox.
    #[arg(long)]
    inbox: bool,
    /// Out of every project, but not in the inbox.
    #[arg(long)]
    no_project: bool,
}

impl PlaceArgs {
    fn location(&self, store: &Store) -> Result<Option<Location>> {
        Ok(if let Some(project) = &self.project {
            Some(Location::Project(store.world()?.find_project(project)?.id))
        } else if self.inbox {
            Some(Location::Inbox)
        } else if self.no_project {
            Some(Location::NoProject)
        } else {
            None
        })
    }
}

#[derive(Args)]
struct AddArgs {
    /// The title. Several words need no quotes.
    #[arg(required = true)]
    title: Vec<String>,
    #[command(flatten)]
    place: PlaceArgs,
    /// Make it a subtask of this task.
    #[arg(long)]
    parent: Option<String>,
    #[arg(long, short)]
    note: Option<String>,
    /// A page, file, or ticket: https://…, file:///…
    #[arg(long, short)]
    url: Option<String>,
    /// Flag it.
    #[arg(long, short)]
    flag: bool,
    /// Planned day: today, tomorrow, fri, +3d, 2026-10-05, optionally with a time.
    #[arg(long)]
    planned: Option<String>,
    /// Due day, as for --planned.
    #[arg(long)]
    due: Option<String>,
    /// Defer until a day, as for --planned.
    #[arg(long, conflicts_with = "defer_indefinitely")]
    defer: Option<String>,
    /// Defer with no end date.
    #[arg(long)]
    defer_indefinitely: bool,
    /// Tags, by path or name. Repeat for several.
    #[arg(long = "tag", short)]
    tags: Vec<String>,
}

#[derive(Args)]
#[group(skip)]
struct LsArgs {
    /// The inbox.
    #[arg(long, group = "list")]
    inbox: bool,
    /// A project's open tasks.
    #[arg(long, short, group = "list")]
    project: Option<String>,
    /// Open tasks with this tag or one below it.
    #[arg(long, short, group = "list")]
    tag: Option<String>,
    /// Open tasks flagged by themselves or their project, inbox included.
    #[arg(long, short, group = "list")]
    flagged: bool,
    /// Every task, Done and Dropped included.
    #[arg(long, group = "list")]
    everything: bool,
    /// In the open stream or flagged, include deferred and unavailable tasks.
    #[arg(long, short, conflicts_with_all = ["inbox", "project", "tag", "everything"])]
    all: bool,
}

#[derive(Args)]
struct EditArgs {
    task: String,
    #[arg(long)]
    title: Option<String>,
    #[arg(long, short)]
    note: Option<String>,
    #[arg(long, conflicts_with = "note")]
    no_note: bool,
    #[arg(long, short)]
    url: Option<String>,
    #[arg(long, conflicts_with = "url")]
    no_url: bool,
    #[arg(long)]
    flag: bool,
    #[arg(long, conflicts_with = "flag")]
    no_flag: bool,
    #[arg(long)]
    planned: Option<String>,
    #[arg(long, conflicts_with = "planned")]
    no_planned: bool,
    #[arg(long)]
    due: Option<String>,
    #[arg(long, conflicts_with = "due")]
    no_due: bool,
    #[arg(long)]
    defer: Option<String>,
    #[arg(long, conflicts_with = "defer")]
    defer_indefinitely: bool,
    #[arg(long, conflicts_with_all = ["defer", "defer_indefinitely"])]
    no_defer: bool,
    /// Make it a subtask of this task.
    #[arg(long)]
    parent: Option<String>,
    /// Make it a top-level task again.
    #[arg(long, conflicts_with = "parent")]
    no_parent: bool,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let output = Output::new(cli.json);

    match run(cli, &output) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            output.error(&error);
            ExitCode::from(error.exit as u8)
        }
    }
}

/// What a command needs: the local store, and the server when online.
struct Context {
    store: Store,
    server: Option<String>,
    offline: bool,
}

impl Context {
    fn open(cli: &Cli) -> Result<Context> {
        let server = match &cli.server {
            Some(server) => Some(normalize_server(server)?),
            None => default_server()?,
        };
        Context::open_with(server, cli.db.clone(), cli.offline)
    }

    fn open_with(server: Option<String>, db: Option<PathBuf>, offline: bool) -> Result<Context> {
        let path = match (&db, &server) {
            (Some(path), _) => {
                if let Some(dir) = path.parent() {
                    std::fs::create_dir_all(dir)?;
                }
                path.clone()
            }
            (None, Some(server)) => {
                paths::create_data_dir()?.join(format!("{}.db", paths::server_slug(server)))
            }
            (None, None) => return Err(CliError::not_signed_in()),
        };

        Ok(Context {
            store: Store::open(&path)?,
            server,
            offline,
        })
    }

    fn tokens(&self) -> Option<TokenStore> {
        self.server.as_deref().map(TokenStore::new)
    }

    /// Syncs, reporting a failure instead of returning it.
    fn try_sync(&mut self) -> Option<String> {
        if self.offline {
            return Some("offline".into());
        }
        let (Some(server), Some(tokens)) = (self.server.clone(), self.tokens()) else {
            return Some("not signed in".into());
        };

        match sync::sync(&mut self.store, &Api::new(&server), &tokens) {
            Ok(_) => None,
            Err(e) => Some(e.message),
        }
    }

    /// Before a read: sync if the last one is stale.
    fn refresh(&mut self) -> Option<String> {
        let stale = match self.store.last_synced_at() {
            Ok(Some(at)) => Timestamp::now().as_second() - at.as_second() > STALE_AFTER_SECONDS,
            _ => true,
        };
        if stale { self.try_sync() } else { None }
    }

    /// Refuses a write on a device signed in read-only.
    fn check_writable(&self) -> Result<()> {
        if let Some(tokens) = self.tokens()
            && let Some(stored) = tokens.load()?
            && !stored.scope.split(' ').any(|s| s == "sync:write")
        {
            return Err(CliError::new(
                "read_only",
                4,
                "This device is signed in read-only. Run `marskal login` to allow changes.",
            ));
        }
        Ok(())
    }

    fn task_id(&self, key: &str) -> Result<Uuid> {
        Ok(self.store.world()?.find_task(key)?.id)
    }

    fn project_id(&self, key: &str) -> Result<Uuid> {
        Ok(self.store.world()?.find_project(key)?.id)
    }

    fn tag_id(&self, key: &str) -> Result<Uuid> {
        Ok(self.store.world()?.find_tag(key)?.id)
    }
}

fn zone() -> TimeZone {
    TimeZone::system()
}

fn when(text: &Option<String>, field: DateField) -> Result<Option<Timestamp>> {
    text.as_deref()
        .map(|text| {
            dates::parse(text, field, &zone(), Timestamp::now())
                .ok_or_else(|| CliError::usage(format!("not a day or time: {text}")))
        })
        .transpose()
}

fn run(cli: Cli, output: &Output) -> Result<()> {
    match &cli.command {
        Command::Login {
            read_only,
            no_browser,
        } => {
            let server = match &cli.server {
                Some(server) => normalize_server(server)?,
                None => default_server()?.ok_or_else(|| {
                    CliError::usage("Give the server: marskal login --server https://…")
                })?,
            };

            let api = Api::new(&server);
            let tokens = TokenStore::new(&server);
            // offline_access is what earns a refresh token (ADR 0021).
            let scope = if *read_only {
                "offline_access sync:read"
            } else {
                "offline_access sync:read sync:write"
            };

            let signed_in = auth::login(&api, &tokens, scope, !no_browser)?;

            State {
                server: Some(server.clone()),
            }
            .save()?;
            // Where later commands look first. If it names another server,
            // say so: signing in here does not change it.
            let shadowed = match std::env::var("MARSKAL_SERVER") {
                Ok(env) if !env.is_empty() => Some((normalize_server(&env)?, "MARSKAL_SERVER")),
                _ => Config::load()?.server()?.map(|c| (c, "config.toml")),
            }
            .filter(|(other, _)| *other != server);

            let mut context =
                Context::open_with(Some(server.clone()), cli.db.clone(), cli.offline)?;
            let unsynced = context.try_sync();
            output.login(&server, &signed_in.scope, shadowed, unsynced.as_deref());
            Ok(())
        }

        Command::Logout { forget } => {
            let context = Context::open(&cli)?;
            if let (Some(server), Some(tokens)) = (&context.server, context.tokens()) {
                if let Some(stored) = tokens.load()?
                    && !cli.offline
                {
                    let _ = Api::new(server).revoke(&stored.refresh_token);
                }
                tokens.delete()?;
            }

            let pending = context.store.pending_count()?;
            if *forget {
                let path = cli.db.clone().or_else(|| {
                    context
                        .server
                        .as_ref()
                        .map(|s| paths::data_dir().join(format!("{}.db", paths::server_slug(s))))
                });
                drop(context);
                if let Some(path) = path {
                    for suffix in ["", "-wal", "-shm"] {
                        let _ = std::fs::remove_file(format!("{}{suffix}", path.display()));
                    }
                }
            }

            output.logout(*forget, pending);
            Ok(())
        }

        Command::Sync => {
            let mut context = Context::open(&cli)?;
            if cli.offline {
                return Err(CliError::usage("sync cannot run --offline"));
            }
            let server = context.server.clone().ok_or_else(CliError::not_signed_in)?;
            let tokens = context.tokens().ok_or_else(CliError::not_signed_in)?;
            let report = sync::sync(&mut context.store, &Api::new(&server), &tokens)?;
            output.synced(&report, &context.store.rejections(true)?);
            context.store.mark_rejections_seen()?;
            Ok(())
        }

        Command::Status => {
            let context = Context::open(&cli)?;
            let signed_in = match context.tokens() {
                Some(tokens) => tokens.load()?.map(|t| t.scope),
                None => None,
            };
            output.status(
                context.server.as_deref(),
                signed_in.as_deref(),
                &context.store.status()?,
            );
            Ok(())
        }

        Command::Add(args) => {
            let mut context = Context::open(&cli)?;
            context.check_writable()?;

            let parent_id = args
                .parent
                .as_deref()
                .map(|p| context.task_id(p))
                .transpose()?;
            let tags: Vec<Uuid> = args
                .tags
                .iter()
                .map(|t| context.tag_id(t))
                .collect::<Result<_>>()?;

            let id = context.store.add_task(NewTask {
                title: args.title.join(" "),
                notes: args.note.clone(),
                url: args.url.clone(),
                flagged: args.flag,
                location: args.place.location(&context.store)?,
                parent_id,
                defer_until: when(&args.defer, DateField::Defer)?,
                deferred_indefinitely: args.defer_indefinitely,
                planned_at: when(&args.planned, DateField::Planned)?,
                due_at: when(&args.due, DateField::Due)?,
            })?;

            for tag in tags {
                context.store.tag_task(id, tag)?;
            }

            let unsynced = context.try_sync();
            let world = context.store.world()?;
            output.task(
                &world,
                world.task(id).expect("just added"),
                "Added",
                unsynced.as_deref(),
            );
            Ok(())
        }

        Command::Ls(args) => {
            let mut context = Context::open(&cli)?;
            let unsynced = context.refresh();

            let filter = if args.inbox {
                TaskFilter::Inbox
            } else if let Some(project) = &args.project {
                TaskFilter::Project(context.project_id(project)?)
            } else if let Some(tag) = &args.tag {
                TaskFilter::Tag(context.tag_id(tag)?)
            } else if args.flagged {
                TaskFilter::Flagged {
                    unavailable: args.all,
                }
            } else if args.everything {
                TaskFilter::All
            } else {
                TaskFilter::Open {
                    unavailable: args.all,
                }
            };

            let world = context.store.world()?;
            output.tasks(&world.tasks(filter), unsynced.as_deref());
            Ok(())
        }

        Command::Show { task } => {
            let mut context = Context::open(&cli)?;
            let unsynced = context.refresh();
            let world = context.store.world()?;
            output.task(&world, world.find_task(task)?, "", unsynced.as_deref());
            Ok(())
        }

        Command::Open { task } => {
            let mut context = Context::open(&cli)?;
            let unsynced = context.refresh();
            let world = context.store.world()?;
            match world.find_task(task)?.url.as_deref() {
                Some(url) if marskal_sync::url::valid(url) => {
                    auth::open(url);
                    output.opened(url, unsynced.as_deref());
                    Ok(())
                }
                _ => Err(CliError::new("no_url", 3, "That task has no URL.")),
            }
        }

        Command::Done { tasks } => set_state(&cli, output, tasks, TaskState::Done, "Done"),
        Command::Drop { tasks } => set_state(&cli, output, tasks, TaskState::Dropped, "Dropped"),
        Command::Reopen { tasks } => set_state(&cli, output, tasks, TaskState::ToDo, "Reopened"),

        Command::Edit(args) => {
            let mut context = Context::open(&cli)?;
            context.check_writable()?;
            let id = context.task_id(&args.task)?;

            let clear_or =
                |clear: bool, text: &Option<String>, field| -> Result<Option<Option<Timestamp>>> {
                    Ok(if clear {
                        Some(None)
                    } else {
                        when(text, field)?.map(Some)
                    })
                };

            context.store.edit_task(
                id,
                TaskPatch {
                    title: args.title.clone(),
                    notes: if args.no_note {
                        Some(None)
                    } else {
                        args.note.clone().map(Some)
                    },
                    url: if args.no_url {
                        Some(None)
                    } else {
                        args.url.clone().map(Some)
                    },
                    flagged: if args.flag {
                        Some(true)
                    } else if args.no_flag {
                        Some(false)
                    } else {
                        None
                    },
                    planned_at: clear_or(args.no_planned, &args.planned, DateField::Planned)?,
                    due_at: clear_or(args.no_due, &args.due, DateField::Due)?,
                    defer_until: clear_or(args.no_defer, &args.defer, DateField::Defer)?,
                    defer_indefinitely: args.defer_indefinitely,
                },
            )?;

            if args.no_parent {
                context.store.set_parent(id, None)?;
            } else if let Some(parent) = &args.parent {
                let parent = context.task_id(parent)?;
                context.store.set_parent(id, Some(parent))?;
            }

            let unsynced = context.try_sync();
            let world = context.store.world()?;
            output.task(
                &world,
                world.task(id).expect("still there"),
                "Changed",
                unsynced.as_deref(),
            );
            Ok(())
        }

        Command::Move { task, to } => {
            let mut context = Context::open(&cli)?;
            context.check_writable()?;
            let id = context.task_id(task)?;
            let location = to
                .location(&context.store)?
                .ok_or_else(|| CliError::usage("Say where: --project, --inbox, or --no-project"))?;
            context.store.move_task(id, location)?;

            let unsynced = context.try_sync();
            let world = context.store.world()?;
            output.task(
                &world,
                world.task(id).expect("still there"),
                "Moved",
                unsynced.as_deref(),
            );
            Ok(())
        }

        Command::Rm { tasks } => {
            let mut context = Context::open(&cli)?;
            context.check_writable()?;
            let ids: Vec<Uuid> = tasks
                .iter()
                .map(|t| context.task_id(t))
                .collect::<Result<_>>()?;
            for id in &ids {
                context.store.delete_task(*id)?;
            }
            let unsynced = context.try_sync();
            output.ids("Deleted", &ids, unsynced.as_deref());
            Ok(())
        }

        Command::Tag { task, tag } | Command::Untag { task, tag } => {
            let mut context = Context::open(&cli)?;
            context.check_writable()?;
            let task_id = context.task_id(task)?;
            let tag_id = context.tag_id(tag)?;

            if matches!(cli.command, Command::Tag { .. }) {
                context.store.tag_task(task_id, tag_id)?;
            } else {
                context.store.untag_task(task_id, tag_id)?;
            }

            let unsynced = context.try_sync();
            let world = context.store.world()?;
            output.task(
                &world,
                world.task(task_id).expect("still there"),
                "Tagged",
                unsynced.as_deref(),
            );
            Ok(())
        }

        Command::Projects { action } => {
            let mut context = Context::open(&cli)?;
            match action {
                None => {
                    let unsynced = context.refresh();
                    output.projects(&context.store.world()?, unsynced.as_deref());
                }
                Some(ProjectAction::Add {
                    title,
                    folder,
                    url,
                    flag,
                }) => {
                    context.check_writable()?;
                    let folder_id = match folder {
                        Some(folder) => Some(context.store.world()?.find_folder(folder)?.id),
                        None => None,
                    };
                    let id = context.store.add_project(NewProject {
                        title: title.join(" "),
                        notes: None,
                        url: url.clone(),
                        flagged: *flag,
                        folder_id,
                    })?;
                    let unsynced = context.try_sync();
                    output.ids("Added project", &[id], unsynced.as_deref());
                }
                Some(
                    ProjectAction::Done { project }
                    | ProjectAction::Drop { project }
                    | ProjectAction::Reopen { project },
                ) => {
                    context.check_writable()?;
                    let id = context.project_id(project)?;
                    let (state, verb) = match action {
                        Some(ProjectAction::Done { .. }) => (TaskState::Done, "Done"),
                        Some(ProjectAction::Drop { .. }) => (TaskState::Dropped, "Dropped"),
                        _ => (TaskState::ToDo, "Reopened"),
                    };
                    context.store.set_project_state(id, state)?;
                    let unsynced = context.try_sync();
                    output.ids(verb, &[id], unsynced.as_deref());
                }
                Some(ProjectAction::Flag { project } | ProjectAction::Unflag { project }) => {
                    context.check_writable()?;
                    let id = context.project_id(project)?;
                    let flag = matches!(action, Some(ProjectAction::Flag { .. }));
                    context.store.set_project_flagged(id, flag)?;
                    let unsynced = context.try_sync();
                    let verb = if flag { "Flagged" } else { "Unflagged" };
                    output.ids(verb, &[id], unsynced.as_deref());
                }
            }
            Ok(())
        }

        Command::Tags { action } => {
            let mut context = Context::open(&cli)?;
            match action {
                None => {
                    let unsynced = context.refresh();
                    output.tags(&context.store.world()?, unsynced.as_deref());
                }
                Some(TagAction::Add { name, parent }) => {
                    context.check_writable()?;
                    let parent = parent.as_deref().map(|p| context.tag_id(p)).transpose()?;
                    let id = context.store.add_tag(name, parent)?;
                    let unsynced = context.try_sync();
                    output.ids("Added tag", &[id], unsynced.as_deref());
                }
            }
            Ok(())
        }

        Command::Rejections => {
            let mut context = Context::open(&cli)?;
            output.rejections(&context.store.rejections(false)?);
            context.store.mark_rejections_seen()?;
            Ok(())
        }
    }
}

fn set_state(
    cli: &Cli,
    output: &Output,
    tasks: &[String],
    state: TaskState,
    verb: &str,
) -> Result<()> {
    let mut context = Context::open(cli)?;
    context.check_writable()?;

    if tasks.is_empty() {
        return Err(CliError::usage("Name at least one task"));
    }

    let ids: Vec<Uuid> = tasks
        .iter()
        .map(|t| context.task_id(t))
        .collect::<Result<_>>()?;
    for id in &ids {
        context.store.set_task_state(*id, state)?;
    }

    let unsynced = context.try_sync();
    output.ids(verb, &ids, unsynced.as_deref());
    Ok(())
}
