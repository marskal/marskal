use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use jiff::Timestamp;
use marskal_sync::{
    Anchor, Clock, Entity, Frequency, HomeView, Keymap, Location, Mode, NewProject, NewTask, Op,
    PullResponse, PullUser, PushResult, PushStatus, Store, TaskFilter, TaskPatch, TaskState,
};
use serde_json::{Map, Value, json};
use uuid::Uuid;

#[derive(Clone)]
struct FixedClock(Arc<Mutex<Timestamp>>);

impl FixedClock {
    fn at(text: &str) -> FixedClock {
        FixedClock(Arc::new(Mutex::new(text.parse().unwrap())))
    }

    fn set(&self, text: &str) {
        *self.0.lock().unwrap() = text.parse().unwrap();
    }
}

impl Clock for FixedClock {
    fn now(&self) -> Timestamp {
        *self.0.lock().unwrap()
    }
}

fn store() -> (Store, FixedClock) {
    let clock = FixedClock::at("2026-10-02T09:00:00Z");
    (
        Store::open_in_memory().unwrap().with_clock(clock.clone()),
        clock,
    )
}

fn capture(store: &mut Store, title: &str) -> Uuid {
    store
        .add_task(NewTask {
            title: title.into(),
            ..NewTask::default()
        })
        .unwrap()
}

fn task_row(id: Uuid, title: &str, extra: Value) -> Map<String, Value> {
    let mut row = json!({
        "id": id.to_string(),
        "title": title,
        "notes": null,
        "state": "to_do",
        "inbox": true,
        "project_id": null,
        "parent_id": null,
        "rank": "V",
        "defer_until": null,
        "deferred_indefinitely": false,
        "planned_at": null,
        "due_at": null,
        "resolved_at": null,
        "discarded_at": null,
        "inserted_at": "2026-10-01T08:00:00Z",
        "updated_at": "2026-10-01T08:00:00Z"
    });
    for (key, value) in extra.as_object().unwrap() {
        row[key] = value.clone();
    }
    row.as_object().unwrap().clone()
}

fn pull(cursor: i64, snapshot: bool, rows: Vec<(&str, Map<String, Value>)>) -> PullResponse {
    let mut by_type: BTreeMap<String, Vec<Map<String, Value>>> = BTreeMap::new();
    for (entity, row) in rows {
        by_type.entry(entity.to_string()).or_default().push(row);
    }
    PullResponse {
        cursor,
        snapshot,
        more: false,
        user: PullUser {
            id: "u1".into(),
            timezone: "Europe/Copenhagen".into(),
        },
        rows: by_type,
        gone: vec![],
    }
}

fn accepted(store: &mut Store) {
    let results: Vec<PushResult> = store
        .pending(1000)
        .unwrap()
        .into_iter()
        .map(|command| PushResult {
            id: Some(command.id),
            status: PushStatus::Applied,
            reason: None,
            errors: None,
        })
        .collect();
    store.record_push(&results).unwrap();
}

fn titles(store: &Store, filter: TaskFilter) -> Vec<String> {
    store
        .world()
        .unwrap()
        .tasks(filter)
        .into_iter()
        .map(|v| v.task.title)
        .collect()
}

#[test]
fn a_capture_lands_in_the_inbox_and_the_outbox() {
    let (mut store, _clock) = store();
    let id = capture(&mut store, "Bread");

    assert_eq!(titles(&store, TaskFilter::Inbox), ["Bread"]);

    let pending = store.pending(10).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].entity, Entity::Task);
    assert_eq!(pending[0].entity_id, id);
    assert_eq!(pending[0].op, Op::Insert);
    assert_eq!(pending[0].fields["title"], "Bread");
    assert_eq!(pending[0].fields["inbox"], true);
    assert!(pending[0].fields["rank"].is_string());
    assert_eq!(id.get_version_num(), 7);
}

#[test]
fn a_new_inbox_task_goes_on_top() {
    let (mut store, _clock) = store();
    capture(&mut store, "First");
    capture(&mut store, "Second");
    assert_eq!(titles(&store, TaskFilter::Inbox), ["Second", "First"]);
}

#[test]
fn pull_keeps_a_pending_field_and_takes_the_rest() {
    let (mut store, _clock) = store();
    let id = Uuid::now_v7();
    store
        .apply_pull(&pull(
            1,
            true,
            vec![("task", task_row(id, "Milk", json!({})))],
        ))
        .unwrap();

    store
        .edit_task(
            id,
            TaskPatch {
                title: Some("Oat milk".into()),
                ..TaskPatch::default()
            },
        )
        .unwrap();

    // The server meanwhile has the old title, and another device checked it off.
    let server = task_row(
        id,
        "Milk",
        json!({ "state": "done", "resolved_at": "2026-10-02T08:30:00Z" }),
    );
    store
        .apply_pull(&pull(2, false, vec![("task", server)]))
        .unwrap();

    let world = store.world().unwrap();
    let task = world.task(id).unwrap();
    assert_eq!(task.title, "Oat milk");
    assert_eq!(task.state, TaskState::Done);
    assert_eq!(task.resolved_at.as_deref(), Some("2026-10-02T08:30:00Z"));
}

#[test]
fn discard_wins_over_a_pending_edit() {
    let (mut store, _clock) = store();
    let id = Uuid::now_v7();
    store
        .apply_pull(&pull(
            1,
            true,
            vec![("task", task_row(id, "Milk", json!({})))],
        ))
        .unwrap();
    store
        .edit_task(
            id,
            TaskPatch {
                title: Some("Oat milk".into()),
                ..TaskPatch::default()
            },
        )
        .unwrap();

    let gone = task_row(
        id,
        "Milk",
        json!({ "discarded_at": "2026-10-02T08:00:00Z" }),
    );
    store
        .apply_pull(&pull(2, false, vec![("task", gone)]))
        .unwrap();

    assert!(store.world().unwrap().task(id).is_none());
}

#[test]
fn a_local_resolve_keeps_its_resolved_at_until_pushed() {
    let (mut store, clock) = store();
    let id = Uuid::now_v7();
    store
        .apply_pull(&pull(
            1,
            true,
            vec![("task", task_row(id, "Milk", json!({})))],
        ))
        .unwrap();

    clock.set("2026-10-02T10:00:00Z");
    store.set_task_state(id, TaskState::Done).unwrap();
    store
        .apply_pull(&pull(
            2,
            false,
            vec![("task", task_row(id, "Milk", json!({})))],
        ))
        .unwrap();

    let world = store.world().unwrap();
    let task = world.task(id).unwrap();
    assert_eq!(task.state, TaskState::Done);
    assert_eq!(task.resolved_at.as_deref(), Some("2026-10-02T10:00:00Z"));

    let pending = store.pending(10).unwrap();
    assert_eq!(pending[0].at.as_deref(), Some("2026-10-02T10:00:00Z"));
}

#[test]
fn accepted_commands_leave_the_outbox() {
    let (mut store, _clock) = store();
    capture(&mut store, "Bread");
    accepted(&mut store);
    assert_eq!(store.pending_count().unwrap(), 0);
    assert_eq!(store.status().unwrap().pending, 0);
}

#[test]
fn a_rejection_is_kept_and_asks_for_a_snapshot() {
    let (mut store, _clock) = store();
    store.apply_pull(&pull(7, true, vec![])).unwrap();
    assert_eq!(store.pull_cursor().unwrap(), Some(7));

    capture(&mut store, "Bread");
    let command = store.pending(1).unwrap().remove(0);

    let summary = store
        .record_push(&[PushResult {
            id: Some(command.id),
            status: PushStatus::Rejected,
            reason: Some("invalid".into()),
            errors: Some(json!({ "title": ["is too long"] })),
        }])
        .unwrap();

    assert_eq!(summary.rejected, 1);
    assert_eq!(store.pending_count().unwrap(), 0);
    assert_eq!(store.pull_cursor().unwrap(), None);

    let rejections = store.rejections(true).unwrap();
    assert_eq!(rejections.len(), 1);
    assert_eq!(rejections[0].reason, "invalid");

    // The snapshot after it drops the refused row.
    store.apply_pull(&pull(8, true, vec![])).unwrap();
    assert!(titles(&store, TaskFilter::Inbox).is_empty());
    assert_eq!(store.pull_cursor().unwrap(), Some(8));
}

#[test]
fn a_snapshot_drops_rows_the_server_lacks_but_keeps_unpushed_ones() {
    let (mut store, _clock) = store();
    let old = Uuid::now_v7();
    store
        .apply_pull(&pull(
            1,
            true,
            vec![("task", task_row(old, "Old", json!({})))],
        ))
        .unwrap();
    capture(&mut store, "New");

    store.apply_pull(&pull(2, true, vec![])).unwrap();
    assert_eq!(titles(&store, TaskFilter::Inbox), ["New"]);
}

#[test]
fn a_move_takes_subtasks_along_and_leaves_the_parent() {
    let (mut store, _clock) = store();
    let project = store
        .add_project(marskal_sync::NewProject {
            title: "Trip".into(),
            ..Default::default()
        })
        .unwrap();

    let parent = capture(&mut store, "Pack");
    let child = store
        .add_task(NewTask {
            title: "Socks".into(),
            parent_id: Some(parent),
            ..NewTask::default()
        })
        .unwrap();

    store.move_task(parent, Location::Project(project)).unwrap();

    let world = store.world().unwrap();
    assert_eq!(world.task(child).unwrap().project_id, Some(project));
    assert!(!world.task(child).unwrap().inbox);
    assert_eq!(
        titles(&store, TaskFilter::Project(project)),
        ["Pack", "Socks"]
    );

    store.move_task(child, Location::NoProject).unwrap();
    let world = store.world().unwrap();
    assert_eq!(world.task(child).unwrap().parent_id, None);

    // The child's move patches only its location; the server places it.
    let last = store.pending(100).unwrap().pop().unwrap();
    assert_eq!(
        last.fields.keys().collect::<Vec<_>>(),
        ["inbox", "project_id"]
    );
}

#[test]
fn a_task_cannot_go_under_its_own_subtask() {
    let (mut store, _clock) = store();
    let parent = capture(&mut store, "Pack");
    let child = store
        .add_task(NewTask {
            title: "Socks".into(),
            parent_id: Some(parent),
            ..NewTask::default()
        })
        .unwrap();

    assert!(store.set_parent(parent, Some(child)).is_err());
    assert_eq!(store.pending_count().unwrap(), 2);
}

#[test]
fn the_open_stream_leaves_out_resolved_deferred_and_unavailable_tasks() {
    let (mut store, clock) = store();
    let project = store
        .add_project(marskal_sync::NewProject {
            title: "Garden".into(),
            ..Default::default()
        })
        .unwrap();

    let add = |store: &mut Store, title: &str| {
        store
            .add_task(NewTask {
                title: title.into(),
                location: Some(Location::Project(project)),
                ..NewTask::default()
            })
            .unwrap()
    };

    let dig = add(&mut store, "Dig");
    let done_parent = add(&mut store, "Plant");
    store
        .add_task(NewTask {
            title: "Water".into(),
            parent_id: Some(done_parent),
            ..NewTask::default()
        })
        .unwrap();
    store.set_task_state(done_parent, TaskState::Done).unwrap();

    let later = add(&mut store, "Prune");
    store
        .edit_task(
            later,
            TaskPatch {
                defer_until: Some(Some("2026-11-01T00:00:00Z".parse().unwrap())),
                ..TaskPatch::default()
            },
        )
        .unwrap();

    let waiting = add(&mut store, "Ask neighbour");
    let tag = store.add_tag("Waiting", None).unwrap();
    store.tag_task(waiting, tag).unwrap();
    capture(&mut store, "In the inbox");

    // An active tag leaves the task available.
    clock.set("2026-10-02T09:05:00Z");
    assert_eq!(
        titles(&store, TaskFilter::Open { unavailable: false }),
        ["Ask neighbour", "Dig"]
    );
    assert_eq!(
        store
            .world()
            .unwrap()
            .view(store.world().unwrap().task(dig).unwrap())
            .project
            .as_deref(),
        Some("Garden")
    );

    // Put the tag on hold, as a pull from the web app would.
    let mut row = Map::new();
    for (key, value) in [
        ("id", json!(tag.to_string())),
        ("name", json!("Waiting")),
        ("parent_id", Value::Null),
        ("state", json!("on_hold")),
        ("rank", json!("V")),
        ("merged_into_id", Value::Null),
        ("discarded_at", Value::Null),
    ] {
        row.insert(key.into(), value);
    }
    accepted(&mut store);
    store
        .apply_pull(&pull(3, false, vec![("tag", row)]))
        .unwrap();

    assert_eq!(
        titles(&store, TaskFilter::Open { unavailable: false }),
        ["Dig"]
    );
    assert_eq!(
        titles(&store, TaskFilter::Open { unavailable: true }),
        ["Ask neighbour", "Prune", "Dig"]
    );
}

#[test]
fn untag_and_tag_again_use_the_same_link_row() {
    let (mut store, _clock) = store();
    let task = capture(&mut store, "Milk");
    let tag = store.add_tag("Shop", None).unwrap();

    store.tag_task(task, tag).unwrap();
    store.untag_task(task, tag).unwrap();
    store.tag_task(task, tag).unwrap();

    let links: Vec<_> = store
        .pending(10)
        .unwrap()
        .into_iter()
        .filter(|c| c.entity == Entity::TaskTag)
        .collect();

    assert_eq!(links.len(), 3);
    assert!(links.iter().all(|c| c.entity_id == links[0].entity_id));
    assert!(links[1].fields["discarded_at"].is_string());
    assert_eq!(links[2].fields["discarded_at"], Value::Null);

    let world = store.world().unwrap();
    assert_eq!(world.view(world.task(task).unwrap()).tags[0].path, ["Shop"]);
}

// ADR 0014's acceptance scenario, from the phone's side: offline it checks
// one item off and adds another; the laptop renames a third.
#[test]
fn offline_edits_and_a_remote_rename_all_survive() {
    let (mut store, _clock) = store();
    let (milk, eggs) = (Uuid::now_v7(), Uuid::now_v7());
    store
        .apply_pull(&pull(
            1,
            true,
            vec![
                ("task", task_row(milk, "Milk", json!({}))),
                ("task", task_row(eggs, "Eggs", json!({}))),
            ],
        ))
        .unwrap();

    store.set_task_state(milk, TaskState::Done).unwrap();
    let bread = capture(&mut store, "Bread");

    // A widget could count the remaining items from local rows alone.
    assert_eq!(titles(&store, TaskFilter::Inbox).len(), 2);

    accepted(&mut store);
    let server = vec![
        (
            "task",
            task_row(
                milk,
                "Milk",
                json!({ "state": "done", "resolved_at": "2026-10-02T09:00:00Z" }),
            ),
        ),
        ("task", task_row(eggs, "Free-range eggs", json!({}))),
        ("task", task_row(bread, "Bread", json!({ "rank": "G" }))),
    ];
    store.apply_pull(&pull(4, false, server)).unwrap();

    let world = store.world().unwrap();
    assert_eq!(world.task(milk).unwrap().state, TaskState::Done);
    assert_eq!(world.task(eggs).unwrap().title, "Free-range eggs");
    assert_eq!(world.task(bread).unwrap().title, "Bread");
}

#[test]
fn two_processes_share_one_file() {
    let dir = std::env::temp_dir().join(format!("marskal-sync-{}", Uuid::now_v7()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("marskal.db");

    let mut cli = Store::open(&path).unwrap();
    let tui = Store::open(&path).unwrap();
    let before = tui.data_version().unwrap();

    capture(&mut cli, "From the command line");

    assert_ne!(tui.data_version().unwrap(), before);
    assert_eq!(titles(&tui, TaskFilter::Inbox), ["From the command line"]);

    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn ids_resolve_by_prefix() {
    let (mut store, _clock) = store();
    let id = capture(&mut store, "Bread");
    let world = store.world().unwrap();
    assert_eq!(world.find_task(&id.to_string()[..8]).unwrap().id, id);
    assert_eq!(
        world.find_task(&marskal_sync::ids::short(&id)).unwrap().id,
        id
    );
    assert!(world.find_task("zzzz").is_err());
}

#[test]
fn a_pulled_series_and_its_occurrence_read_back() {
    let (mut store, _clock) = store();
    let series = Uuid::now_v7();
    let task = Uuid::now_v7();

    let row = json!({
        "id": series.to_string(),
        "kind": "task",
        "mode": "regular",
        "anchor": "due",
        "interval": 2,
        "frequency": "weeks",
        "weekdays": [2, 5],
        "on_days": [],
        "ends_at": null,
        "end_count": 10,
        "week_start": 7,
        "stopped_at": null,
        "discarded_at": null,
        "inserted_at": "2026-10-01T08:00:00Z",
        "updated_at": "2026-10-01T08:00:00Z"
    });

    let occurrence = task_row(
        task,
        "Trash",
        json!({
            "due_at": "2026-10-09T15:00:00Z",
            "series_id": series.to_string(),
            "occurrence_for": "2026-10-09T15:00:00Z"
        }),
    );

    store
        .apply_pull(&pull(
            1,
            true,
            vec![
                ("recurrence_series", row.as_object().unwrap().clone()),
                ("task", occurrence),
            ],
        ))
        .unwrap();

    let world = store.world().unwrap();
    let read = world.series(series).unwrap();
    assert_eq!(read.mode, Mode::Regular);
    assert_eq!(read.anchor, Anchor::Due);
    assert_eq!(read.frequency, Frequency::Weeks);
    assert_eq!((read.interval, read.end_count), (2, Some(10)));
    assert_eq!(read.weekdays, vec![2, 5]);
    assert_eq!(read.week_start, 7);
    assert!(read.on_days.is_empty());

    let read = world.task(task).unwrap();
    assert_eq!(read.series_id, Some(series));
    assert_eq!(read.occurrence_for.as_deref(), Some("2026-10-09T15:00:00Z"));
}

#[test]
fn pulled_preferences_read_back() {
    let (mut store, _clock) = store();
    assert_eq!(store.preferences().unwrap(), None);

    let user = Uuid::now_v7();
    let row = json!({
        "id": user.to_string(),
        "timezone": "America/New_York",
        "week_start": 7,
        "locale": "en-DK",
        "home_view": "agenda",
        "keymap": "vim",
        "inserted_at": "2026-10-01T08:00:00Z",
        "updated_at": "2026-10-01T08:00:00Z"
    });

    store
        .apply_pull(&pull(
            1,
            true,
            vec![("user_preferences", row.as_object().unwrap().clone())],
        ))
        .unwrap();

    let preferences = store.preferences().unwrap().unwrap();
    assert_eq!(preferences.id, user);
    assert_eq!(preferences.timezone, "America/New_York");
    assert_eq!(preferences.week_start, 7);
    assert_eq!(preferences.locale, "en-DK");
    assert_eq!(preferences.home_view, HomeView::Agenda);
    assert_eq!(preferences.keymap, Keymap::Vim);
}

#[test]
fn a_preferences_row_from_before_home_view_reads_as_open_tasks() {
    let dir = std::env::temp_dir().join(format!("marskal-sync-{}", Uuid::now_v7()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("marskal.db");

    let mut store = Store::open(&path).unwrap();
    let user = Uuid::now_v7();
    let row = json!({
        "id": user.to_string(),
        "timezone": "Europe/Copenhagen",
        "week_start": 1,
        "locale": "en-150",
        "home_view": "inbox",
        "inserted_at": "2026-10-01T08:00:00Z",
        "updated_at": "2026-10-01T08:00:00Z"
    });
    store
        .apply_pull(&pull(
            4,
            true,
            vec![("user_preferences", row.as_object().unwrap().clone())],
        ))
        .unwrap();
    assert_eq!(
        store.preferences().unwrap().unwrap().home_view,
        HomeView::Inbox
    );
    drop(store);

    let conn = rusqlite::Connection::open(&path).unwrap();
    let version: i64 = conn
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .unwrap();
    conn.execute_batch(&format!(
        "ALTER TABLE user_preferences DROP COLUMN keymap;
         ALTER TABLE user_preferences DROP COLUMN home_view;
         PRAGMA user_version = {version};",
        version = version - 2
    ))
    .unwrap();
    drop(conn);

    let store = Store::open(&path).unwrap();
    assert_eq!(store.pull_cursor().unwrap(), None);
    let preferences = store.preferences().unwrap().unwrap();
    assert_eq!(preferences.home_view, HomeView::OpenTasks);
    assert_eq!(preferences.keymap, Keymap::Standard);

    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn a_task_carries_a_url() {
    let (mut store, _clock) = store();
    let id = store
        .add_task(NewTask {
            title: "Fix".into(),
            url: Some(" https://jira.example/X-1 ".into()),
            ..NewTask::default()
        })
        .unwrap();

    assert_eq!(
        store.pending(10).unwrap()[0].fields["url"],
        "https://jira.example/X-1"
    );
    let world = store.world().unwrap();
    assert_eq!(
        world.task(id).unwrap().url.as_deref(),
        Some("https://jira.example/X-1")
    );

    store
        .edit_task(
            id,
            TaskPatch {
                url: Some(None),
                ..TaskPatch::default()
            },
        )
        .unwrap();
    assert_eq!(store.world().unwrap().task(id).unwrap().url, None);

    let refused = store.edit_task(
        id,
        TaskPatch {
            url: Some(Some("javascript:alert(1)".into())),
            ..TaskPatch::default()
        },
    );
    assert!(refused.is_err());
    assert_eq!(store.pending(10).unwrap().len(), 2);
}

#[test]
fn a_pulled_url_is_kept() {
    let (mut store, _clock) = store();
    let id = Uuid::now_v7();
    let row = task_row(id, "Read", json!({ "url": "file:///tmp/plan.md" }));
    store
        .apply_pull(&pull(1, true, vec![("task", row)]))
        .unwrap();

    let world = store.world().unwrap();
    assert_eq!(
        world.task(id).unwrap().url.as_deref(),
        Some("file:///tmp/plan.md")
    );
}

#[test]
fn a_database_from_before_urls_asks_for_a_snapshot() {
    let dir = std::env::temp_dir().join(format!("marskal-sync-{}", Uuid::now_v7()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("marskal.db");

    let mut store = Store::open(&path).unwrap();
    store.apply_pull(&pull(7, true, vec![])).unwrap();
    assert_eq!(store.pull_cursor().unwrap(), Some(7));
    drop(store);

    // Back to the schema a client built before URLs left.
    let conn = rusqlite::Connection::open(&path).unwrap();
    conn.execute_batch(
        "ALTER TABLE tasks DROP COLUMN flagged;
         ALTER TABLE projects DROP COLUMN flagged;
         ALTER TABLE tasks DROP COLUMN url;
         ALTER TABLE projects DROP COLUMN url;
         ALTER TABLE recurrence_series DROP COLUMN week_start;
         ALTER TABLE recurrence_series DROP COLUMN on_days;
         ALTER TABLE recurrence_series ADD COLUMN month_days TEXT NOT NULL DEFAULT '[]';
         ALTER TABLE recurrence_series ADD COLUMN month_ordinal INTEGER;
         ALTER TABLE recurrence_series ADD COLUMN month_day_kind TEXT;
         DROP TABLE user_preferences;
         PRAGMA user_version = 2;",
    )
    .unwrap();
    drop(conn);

    let store = Store::open(&path).unwrap();
    assert_eq!(store.pull_cursor().unwrap(), None);

    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn a_flag_on_the_task_or_its_project_puts_it_in_flagged() {
    let (mut store, _clock) = store();
    let home = store
        .add_project(NewProject {
            title: "Home".into(),
            ..NewProject::default()
        })
        .unwrap();
    let paint = store
        .add_task(NewTask {
            title: "Paint".into(),
            location: Some(Location::Project(home)),
            ..NewTask::default()
        })
        .unwrap();
    let milk = store
        .add_task(NewTask {
            title: "Milk".into(),
            flagged: true,
            ..NewTask::default()
        })
        .unwrap();
    store
        .add_task(NewTask {
            title: "Under milk".into(),
            parent_id: Some(milk),
            ..NewTask::default()
        })
        .unwrap();

    assert_eq!(store.pending(10).unwrap()[2].fields["flagged"], true);
    assert_eq!(
        titles(&store, TaskFilter::Flagged { unavailable: false }),
        vec!["Milk"]
    );

    store.set_project_flagged(home, true).unwrap();
    store
        .edit_task(
            milk,
            TaskPatch {
                flagged: Some(false),
                ..TaskPatch::default()
            },
        )
        .unwrap();

    let world = store.world().unwrap();
    let flagged = world.tasks(TaskFilter::Flagged { unavailable: false });
    assert_eq!(flagged.len(), 1);
    assert_eq!(flagged[0].task.id, paint);
    assert!(flagged[0].flagged);
    assert!(!flagged[0].task.flagged);
}

#[test]
fn a_pulled_flag_is_kept() {
    let (mut store, _clock) = store();
    let id = Uuid::now_v7();
    let row = task_row(id, "Call", json!({ "flagged": true }));
    store
        .apply_pull(&pull(1, true, vec![("task", row)]))
        .unwrap();

    assert!(store.world().unwrap().task(id).unwrap().flagged);
}

#[test]
fn the_agenda_is_due_and_planned_tasks_by_time() {
    let (mut store, _clock) = store();
    // The end of 2 October in Copenhagen; the clock reads 11:00 there.
    let until: Timestamp = "2026-10-02T22:00:00Z".parse().unwrap();
    let rows = [
        ("Afternoon", json!({ "planned_at": "2026-10-02T12:00:00Z" })),
        (
            "Missed yesterday",
            json!({ "planned_at": "2026-10-01T07:00:00Z" }),
        ),
        ("Overdue", json!({ "due_at": "2026-09-30T15:00:00Z" })),
        (
            "Due before it is planned",
            json!({ "planned_at": "2026-10-02T06:00:00Z", "due_at": "2026-10-02T15:00:00Z" }),
        ),
        (
            "Planned today, due next week",
            json!({ "planned_at": "2026-10-02T07:00:00Z", "due_at": "2026-10-09T15:00:00Z" }),
        ),
        ("Tomorrow", json!({ "planned_at": "2026-10-02T22:00:00Z" })),
        (
            "Done",
            json!({ "planned_at": "2026-10-02T08:00:00Z", "state": "done" }),
        ),
        (
            "Deferred",
            json!({ "planned_at": "2026-10-02T08:00:00Z", "defer_until": "2026-10-02T10:00:00Z" }),
        ),
        ("Undated", json!({})),
    ];
    let rows = rows
        .into_iter()
        .map(|(title, extra)| ("task", task_row(Uuid::now_v7(), title, extra)))
        .collect();
    store.apply_pull(&pull(1, true, rows)).unwrap();

    let agenda: Vec<(String, String, bool)> = store
        .world()
        .unwrap()
        .agenda(until)
        .into_iter()
        .map(|e| (e.view.task.title, e.at.to_string(), e.due))
        .collect();

    assert_eq!(
        agenda,
        [
            ("Overdue".into(), "2026-09-30T15:00:00Z".into(), true),
            (
                "Missed yesterday".into(),
                "2026-10-01T07:00:00Z".into(),
                false
            ),
            (
                "Planned today, due next week".into(),
                "2026-10-02T07:00:00Z".into(),
                false
            ),
            ("Afternoon".into(), "2026-10-02T12:00:00Z".into(), false),
            (
                "Due before it is planned".into(),
                "2026-10-02T15:00:00Z".into(),
                true
            ),
        ]
    );
}

#[test]
fn a_subtask_is_on_the_agenda_by_its_parent_s_planned() {
    let (mut store, _clock) = store();
    let until: Timestamp = "2026-10-02T22:00:00Z".parse().unwrap();
    let paint = store
        .add_task(NewTask {
            title: "Paint".into(),
            location: Some(Location::NoProject),
            planned_at: Some("2026-10-02T13:00:00Z".parse().unwrap()),
            ..NewTask::default()
        })
        .unwrap();
    store
        .add_task(NewTask {
            title: "Sand".into(),
            parent_id: Some(paint),
            ..NewTask::default()
        })
        .unwrap();

    let agenda: Vec<(String, String)> = store
        .world()
        .unwrap()
        .agenda(until)
        .into_iter()
        .map(|e| (e.view.task.title, e.at.to_string()))
        .collect();
    assert_eq!(
        agenda,
        [
            ("Paint".into(), "2026-10-02T13:00:00Z".into()),
            ("Sand".into(), "2026-10-02T13:00:00Z".into()),
        ]
    );
}
