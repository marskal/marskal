//! Project review (ADR 0026): the fields, the commands, and the projects due.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use jiff::Timestamp;
use jiff::civil::{Date, date};
use marskal_replica::{
    Clock, Entity, NewProject, NewTask, Op, PullResponse, PullUser, Store, TaskState,
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

const USER: &str = "0199a0c0-0000-7000-8000-000000000001";

// A store whose user is in Copenhagen with `default` as the default
// interval, at 23:30 UTC on Jan 30: already Jan 31 on the user's clock.
fn store(default: Option<&str>) -> (Store, FixedClock) {
    let clock = FixedClock::at("2026-01-30T23:30:00Z");
    let mut store = Store::open_in_memory().unwrap().with_clock(clock.clone());
    store
        .apply_pull(&pull(vec![("user_preferences", preferences(default))]))
        .unwrap();
    (store, clock)
}

fn preferences(default: Option<&str>) -> Map<String, Value> {
    object(json!({
        "id": USER,
        "timezone": "Europe/Copenhagen",
        "week_start": 1,
        "locale": "en-DK",
        "home_view": "open_tasks",
        "keymap": "standard",
        "default_review_interval": default,
        "inserted_at": "2026-01-01T08:00:00Z",
        "updated_at": "2026-01-01T08:00:00Z"
    }))
}

fn project_row(id: Uuid, title: &str, extra: Value) -> Map<String, Value> {
    let mut row = json!({
        "id": id.to_string(),
        "title": title,
        "notes": null,
        "url": null,
        "flagged": false,
        "state": "to_do",
        "project_folder_id": null,
        "rank": "V",
        "defer_until": null,
        "deferred_indefinitely": false,
        "planned_at": null,
        "due_at": null,
        "series_id": null,
        "occurrence_for": null,
        "review_interval": "P7D",
        "next_review_on": "2026-01-31",
        "last_reviewed_at": null,
        "resolved_at": null,
        "discarded_at": null,
        "inserted_at": "2026-01-01T08:00:00Z",
        "updated_at": "2026-01-01T08:00:00Z"
    });
    for (key, value) in extra.as_object().unwrap() {
        row[key] = value.clone();
    }
    object(row)
}

fn folder_row(
    id: Uuid,
    name: &str,
    parent: Option<Uuid>,
    state: &str,
    rank: &str,
) -> Map<String, Value> {
    object(json!({
        "id": id.to_string(),
        "name": name,
        "parent_id": parent.map(|p| p.to_string()),
        "state": state,
        "rank": rank,
        "discarded_at": null,
        "inserted_at": "2026-01-01T08:00:00Z",
        "updated_at": "2026-01-01T08:00:00Z"
    }))
}

fn pull(rows: Vec<(&str, Map<String, Value>)>) -> PullResponse {
    let mut by_type: BTreeMap<String, Vec<Map<String, Value>>> = BTreeMap::new();
    for (entity, row) in rows {
        by_type.entry(entity.to_string()).or_default().push(row);
    }
    PullResponse {
        cursor: 1,
        snapshot: false,
        more: false,
        user: PullUser {
            id: USER.into(),
            timezone: "Europe/Copenhagen".into(),
        },
        rows: by_type,
        gone: vec![],
    }
}

fn object(value: Value) -> Map<String, Value> {
    value.as_object().unwrap().clone()
}

fn add(store: &mut Store, new: NewProject) -> Uuid {
    store.add_project(new).unwrap()
}

fn named(title: &str) -> NewProject {
    NewProject {
        title: title.into(),
        ..NewProject::default()
    }
}

fn review(store: &Store, id: Uuid) -> (Option<String>, Option<String>, Option<String>) {
    let world = store.world().unwrap();
    let project = world.project(id).unwrap();
    (
        project.review_interval.clone(),
        project.next_review_on.clone(),
        project.last_reviewed_at.clone(),
    )
}

fn last_fields(store: &Store) -> Map<String, Value> {
    store.pending(1000).unwrap().pop().unwrap().fields
}

fn some(text: &str) -> Option<String> {
    Some(text.to_string())
}

#[test]
fn today_is_on_the_user_s_clock() {
    let (store, _clock) = store(Some("P7D"));
    assert_eq!(store.today().unwrap(), date(2026, 1, 31));
}

#[test]
fn a_new_project_takes_the_default_and_is_due_that_interval_after_today() {
    let (mut store, _clock) = store(Some("P1M"));
    let id = add(&mut store, named("Garden"));

    // Jan 31 plus a month is the end of February.
    assert_eq!(review(&store, id), (some("P1M"), some("2026-02-28"), None));

    let pending = store.pending(10).unwrap();
    let insert = pending.last().unwrap();
    assert_eq!(insert.op, Op::Insert);
    assert_eq!(insert.fields["review_interval"], "P1M");
    assert_eq!(insert.fields["next_review_on"], "2026-02-28");
}

#[test]
fn a_new_project_under_a_never_default_is_never_reviewed() {
    let (mut store, _clock) = store(None);
    let id = add(&mut store, named("Reference"));

    assert_eq!(review(&store, id), (None, None, None));
    // Sent as null, so the server does not put its own default in.
    let fields = last_fields(&store);
    assert_eq!(fields["review_interval"], Value::Null);
    assert_eq!(fields["next_review_on"], Value::Null);
}

#[test]
fn a_new_project_may_name_its_interval_and_first_day() {
    let (mut store, _clock) = store(Some("P7D"));

    let weeks = add(
        &mut store,
        NewProject {
            review_interval: Some(some("p2w")),
            ..named("Taxes")
        },
    );
    assert_eq!(
        review(&store, weeks),
        (some("P14D"), some("2026-02-14"), None)
    );

    let never = add(
        &mut store,
        NewProject {
            review_interval: Some(None),
            ..named("Recipes")
        },
    );
    assert_eq!(review(&store, never), (None, None, None));

    let chosen = add(
        &mut store,
        NewProject {
            next_review_on: Some(date(2026, 3, 1)),
            ..named("Bike")
        },
    );
    assert_eq!(
        review(&store, chosen),
        (some("P7D"), some("2026-03-01"), None)
    );

    let refused = [
        NewProject {
            review_interval: Some(None),
            next_review_on: Some(date(2026, 3, 1)),
            ..named("Never, but a day")
        },
        NewProject {
            review_interval: Some(some("PT1H")),
            ..named("Hourly")
        },
    ];
    for new in refused {
        assert!(store.add_project(new).is_err());
    }
    assert_eq!(store.pending(10).unwrap().len(), 3);
}

#[test]
fn mark_reviewed_counts_the_interval_from_today() {
    let (mut store, clock) = store(Some("P1M"));
    let id = add(&mut store, named("Garden"));

    clock.set("2026-03-31T10:00:00Z");
    store.mark_project_reviewed(id).unwrap();

    assert_eq!(
        review(&store, id),
        (
            some("P1M"),
            some("2026-04-30"),
            some("2026-03-31T10:00:00Z")
        )
    );
    let fields = last_fields(&store);
    assert_eq!(
        fields.keys().collect::<Vec<_>>(),
        ["last_reviewed_at", "next_review_on"]
    );

    store.set_project_review_interval(id, None).unwrap();
    assert!(store.mark_project_reviewed(id).is_err());
    assert!(store.mark_project_reviewed(Uuid::now_v7()).is_err());
}

#[test]
fn a_new_interval_counts_from_the_last_review_or_the_creation_day() {
    let (mut store, clock) = store(Some("P7D"));
    let id = add(&mut store, named("Garden"));

    // Made Jan 31 on the user's clock.
    clock.set("2026-03-10T12:00:00Z");
    store
        .set_project_review_interval(id, Some("P1M1D"))
        .unwrap();
    assert_eq!(
        review(&store, id),
        (some("P1M1D"), some("2026-03-01"), None)
    );
    let fields = last_fields(&store);
    assert_eq!(fields["review_interval"], "P1M1D");
    assert_eq!(fields["next_review_on"], "2026-03-01");

    // Reviewed late on Mar 10 in Copenhagen, which is Mar 11 there.
    clock.set("2026-03-10T23:30:00Z");
    store.mark_project_reviewed(id).unwrap();
    store.set_project_review_interval(id, Some("P2W")).unwrap();
    assert_eq!(
        review(&store, id),
        (
            some("P14D"),
            some("2026-03-25"),
            some("2026-03-10T23:30:00Z")
        )
    );

    store.set_project_review_interval(id, None).unwrap();
    assert_eq!(review(&store, id).0, None);
    assert_eq!(review(&store, id).1, None);
    let fields = last_fields(&store);
    assert_eq!(fields["review_interval"], Value::Null);
    assert_eq!(fields["next_review_on"], Value::Null);

    assert!(store.set_project_review_interval(id, Some("P0D")).is_err());
}

#[test]
fn the_next_review_day_can_be_moved_unless_never() {
    let (mut store, _clock) = store(Some("P7D"));
    let id = add(&mut store, named("Garden"));

    store
        .set_project_next_review_on(id, date(2026, 5, 1))
        .unwrap();
    assert_eq!(review(&store, id).1, some("2026-05-01"));
    assert_eq!(
        last_fields(&store),
        object(json!({ "next_review_on": "2026-05-01" }))
    );

    store.set_project_review_interval(id, None).unwrap();
    assert!(
        store
            .set_project_next_review_on(id, date(2026, 5, 1))
            .is_err()
    );
}

#[test]
fn the_default_interval_is_a_preference_patch() {
    let (mut store, _clock) = store(Some("P7D"));

    store.set_default_review_interval(Some("p1m")).unwrap();
    assert_eq!(
        store
            .preferences()
            .unwrap()
            .unwrap()
            .default_review_interval,
        some("P1M")
    );
    let pending = store.pending(10).unwrap();
    let patch = pending.last().unwrap();
    assert_eq!(patch.entity, Entity::UserPreferences);
    assert_eq!(patch.entity_id.to_string(), USER);
    assert_eq!(patch.op, Op::Patch);
    assert_eq!(
        patch.fields,
        object(json!({ "default_review_interval": "P1M" }))
    );

    // New projects take it; one made before keeps its own.
    let id = add(&mut store, named("Garden"));
    assert_eq!(review(&store, id).0, some("P1M"));

    store.set_default_review_interval(None).unwrap();
    assert_eq!(
        store
            .preferences()
            .unwrap()
            .unwrap()
            .default_review_interval,
        None
    );
    assert_eq!(review(&store, id).0, some("P1M"));

    assert!(store.set_default_review_interval(Some("weekly")).is_err());

    let mut fresh = Store::open_in_memory().unwrap();
    assert!(fresh.set_default_review_interval(Some("P7D")).is_err());
}

#[test]
fn pulled_review_fields_read_back() {
    let (mut store, _clock) = store(Some("P14D"));
    let id = Uuid::now_v7();
    store
        .apply_pull(&pull(vec![(
            "project",
            project_row(
                id,
                "Garden",
                json!({
                    "review_interval": "P1Y2M",
                    "next_review_on": "2026-02-10",
                    "last_reviewed_at": "2025-12-10T09:00:00Z"
                }),
            ),
        )]))
        .unwrap();

    assert_eq!(
        review(&store, id),
        (
            some("P1Y2M"),
            some("2026-02-10"),
            some("2025-12-10T09:00:00Z")
        )
    );
    assert_eq!(
        store
            .preferences()
            .unwrap()
            .unwrap()
            .default_review_interval,
        some("P14D")
    );
}

#[test]
fn a_database_from_before_review_asks_for_a_snapshot() {
    let dir = std::env::temp_dir().join(format!("marskal-replica-{}", Uuid::now_v7()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("marskal.db");

    let mut store = Store::open(&path).unwrap();
    store
        .apply_pull(&PullResponse {
            snapshot: true,
            ..pull(vec![])
        })
        .unwrap();
    assert_eq!(store.pull_cursor().unwrap(), Some(1));
    drop(store);

    let conn = rusqlite::Connection::open(&path).unwrap();
    let version: i64 = conn
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .unwrap();
    conn.execute_batch(&format!(
        "ALTER TABLE projects DROP COLUMN review_interval;
         ALTER TABLE projects DROP COLUMN next_review_on;
         ALTER TABLE projects DROP COLUMN last_reviewed_at;
         ALTER TABLE user_preferences DROP COLUMN default_review_interval;
         PRAGMA user_version = {version};",
        version = version - 1
    ))
    .unwrap();
    drop(conn);

    let store = Store::open(&path).unwrap();
    assert_eq!(store.pull_cursor().unwrap(), None);

    std::fs::remove_dir_all(dir).unwrap();
}

fn due(store: &Store, today: Date) -> Vec<(String, bool, bool, Vec<String>, bool)> {
    store
        .world()
        .unwrap()
        .due_for_review(today)
        .into_iter()
        .map(|view| {
            (
                view.project.title,
                view.deferred,
                view.stalled,
                view.folder_path,
                view.in_dropped_folder,
            )
        })
        .collect()
}

#[test]
fn due_projects_by_day_then_sidebar_order_with_deferral_and_stall() {
    let (mut store, _clock) = store(Some("P7D"));
    let work = Uuid::now_v7();
    let old = Uuid::now_v7();
    let ids: Vec<Uuid> = (0..8).map(|_| Uuid::now_v7()).collect();
    let folder = |id: Uuid| json!(id.to_string());

    store
        .apply_pull(&pull(vec![
            (
                "project_folder",
                folder_row(work, "Work", None, "active", "B"),
            ),
            (
                "project_folder",
                folder_row(old, "Old", Some(work), "dropped", "a"),
            ),
            // Top level, after Work.
            (
                "project",
                project_row(ids[0], "Home", json!({ "rank": "C" })),
            ),
            // In Work, after Old.
            (
                "project",
                project_row(
                    ids[1],
                    "Site",
                    json!({ "rank": "b", "project_folder_id": folder(work) }),
                ),
            ),
            // In Old, a Dropped folder.
            (
                "project",
                project_row(
                    ids[2],
                    "Archive",
                    json!({ "rank": "V", "project_folder_id": folder(old) }),
                ),
            ),
            // Due earlier, so first.
            (
                "project",
                project_row(
                    ids[3],
                    "Overdue",
                    json!({ "rank": "Z", "next_review_on": "2026-01-20" }),
                ),
            ),
            (
                "project",
                project_row(
                    ids[4],
                    "Someday",
                    json!({ "rank": "A", "deferred_indefinitely": true }),
                ),
            ),
            // Not due: later, Never, Done.
            (
                "project",
                project_row(ids[5], "Later", json!({ "next_review_on": "2026-02-01" })),
            ),
            (
                "project",
                project_row(
                    ids[6],
                    "Never",
                    json!({ "review_interval": null, "next_review_on": null }),
                ),
            ),
            (
                "project",
                project_row(
                    ids[7],
                    "Finished",
                    json!({ "state": "done", "resolved_at": "2026-01-10T08:00:00Z" }),
                ),
            ),
        ]))
        .unwrap();

    // Home has an open task; Site has only a deferred one.
    for (title, project, defer) in [
        ("Mow", ids[0], None),
        ("Deploy", ids[1], Some("2026-06-01T00:00:00Z")),
    ] {
        let task = store
            .add_task(NewTask {
                title: title.into(),
                location: Some(marskal_replica::Location::Project(project)),
                defer_until: defer.map(|at: &str| at.parse().unwrap()),
                ..NewTask::default()
            })
            .unwrap();
        assert!(store.world().unwrap().task(task).is_some());
    }

    let today = store.today().unwrap();
    let work_path = vec!["Work".to_string()];
    let old_path = vec!["Work".to_string(), "Old".to_string()];
    assert_eq!(
        due(&store, today),
        [
            ("Overdue".into(), false, true, vec![], false),
            ("Someday".into(), true, false, vec![], false),
            ("Archive".into(), false, true, old_path, true),
            ("Site".into(), false, true, work_path, false),
            ("Home".into(), false, false, vec![], false),
        ]
    );
    assert_eq!(store.world().unwrap().due_for_review_count(today), 5);

    // A day earlier, only the overdue one.
    assert_eq!(
        store
            .world()
            .unwrap()
            .due_for_review_count(date(2026, 1, 30)),
        1
    );

    // Done leaves the list; marking reviewed moves it on.
    store.set_project_state(ids[3], TaskState::Done).unwrap();
    store.mark_project_reviewed(ids[0]).unwrap();
    let titles: Vec<String> = due(&store, today).into_iter().map(|d| d.0).collect();
    assert_eq!(titles, ["Someday", "Archive", "Site"]);
}
