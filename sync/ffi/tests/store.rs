use jiff::Timestamp;
use marskal_sync_ffi::{
    DateField, Defer, LocalDate, LocalTime, Location, NewProject, NewTask, Store, StoreError,
    TaskChange, TaskFilter, TaskState, default_time, local_instant,
};
use serde_json::{Value, json};
use uuid::Uuid;

// A database file of its own, removed when the test ends.
struct Db {
    path: std::path::PathBuf,
    store: Store,
}

impl Db {
    fn new() -> Db {
        let path = std::env::temp_dir().join(format!("marskal-ffi-{}.sqlite", Uuid::now_v7()));
        let store = Store::open(path.to_string_lossy().into_owned()).unwrap();
        Db { path, store }
    }
}

impl Drop for Db {
    fn drop(&mut self) {
        self.store.close();
        for suffix in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{suffix}", self.path.display()));
        }
    }
}

fn capture(store: &Store, title: &str) -> Uuid {
    store
        .add_task(NewTask {
            title: title.into(),
            ..NewTask::default()
        })
        .unwrap()
}

fn at(text: &str) -> Timestamp {
    text.parse().unwrap()
}

fn pull_body(user: &str, rows: Value) -> String {
    json!({
        "cursor": 7,
        "snapshot": true,
        "more": false,
        "user": { "id": user, "timezone": "Europe/Copenhagen" },
        "rows": rows,
        "gone": []
    })
    .to_string()
}

fn task_row(id: Uuid, title: &str) -> Value {
    json!({
        "id": id.to_string(),
        "title": title,
        "notes": null,
        "url": null,
        "flagged": false,
        "state": "to_do",
        "inbox": true,
        "project_id": null,
        "parent_id": null,
        "rank": "V",
        "defer_until": null,
        "deferred_indefinitely": false,
        "planned_at": "2026-10-20T07:00:00Z",
        "due_at": null,
        "series_id": null,
        "occurrence_for": null,
        "resolved_at": null,
        "discarded_at": null,
        "inserted_at": "2026-10-01T08:00:00Z",
        "updated_at": "2026-10-01T08:00:00Z"
    })
}

#[test]
fn a_capture_lands_in_the_inbox_and_waits_to_be_pushed() {
    let db = Db::new();
    let id = capture(&db.store, "  Buy milk ");

    let inbox = db.store.tasks(TaskFilter::Inbox).unwrap();
    assert_eq!(inbox.len(), 1);
    assert_eq!(inbox[0].id, id);
    assert_eq!(inbox[0].title, "Buy milk");
    assert!(inbox[0].inbox);
    assert_eq!(inbox[0].state, TaskState::ToDo);
    assert!(
        db.store
            .tasks(TaskFilter::Open { unavailable: false })
            .unwrap()
            .is_empty()
    );

    assert_eq!(db.store.status().unwrap().pending, 1);
}

#[test]
fn a_blank_title_is_invalid() {
    let db = Db::new();
    let error = db
        .store
        .add_task(NewTask {
            title: "  ".into(),
            ..NewTask::default()
        })
        .unwrap_err();
    assert!(matches!(error, StoreError::Invalid { .. }));
}

#[test]
fn edits_set_and_clear_dates_in_one_command() {
    let db = Db::new();
    let id = db
        .store
        .add_task(NewTask {
            title: "Report".into(),
            due_at: Some(at("2026-10-30T16:00:00Z")),
            ..NewTask::default()
        })
        .unwrap();

    db.store
        .edit_task(
            id,
            vec![
                TaskChange::Title {
                    title: "Quarterly report".into(),
                },
                TaskChange::Planned {
                    at: Some(at("2026-10-21T07:00:00Z")),
                },
                TaskChange::Due { at: None },
                TaskChange::Deferred {
                    deferred: Some(Defer::Indefinitely),
                },
            ],
        )
        .unwrap();

    let task = db.store.task(id).unwrap().unwrap();
    assert_eq!(task.title, "Quarterly report");
    assert_eq!(task.dates.planned_at, Some(at("2026-10-21T07:00:00Z")));
    assert_eq!(task.dates.due_at, None);
    assert!(task.dates.deferred_indefinitely);
    assert!(task.deferred);
    assert_eq!(db.store.status().unwrap().pending, 2);

    db.store
        .edit_task(id, vec![TaskChange::Deferred { deferred: None }])
        .unwrap();
    let task = db.store.task(id).unwrap().unwrap();
    assert!(!task.dates.deferred_indefinitely);
    assert_eq!(task.dates.defer_until, None);
}

#[test]
fn a_task_moves_into_a_project_and_is_resolved() {
    let db = Db::new();
    let project = db
        .store
        .add_project(NewProject {
            title: "Garden".into(),
            ..NewProject::default()
        })
        .unwrap();
    let id = capture(&db.store, "Mow");

    db.store
        .move_task(id, Location::Project { id: project })
        .unwrap();
    let listed = db.store.tasks(TaskFilter::Project { id: project }).unwrap();
    assert_eq!(listed[0].project.as_deref(), Some("Garden"));

    db.store.set_task_state(id, TaskState::Done).unwrap();
    let task = db.store.task(id).unwrap().unwrap();
    assert!(task.resolved);
    assert!(task.resolved_at.is_some());
    assert!(
        db.store
            .tasks(TaskFilter::Project { id: project })
            .unwrap()
            .is_empty()
    );
}

#[test]
fn a_push_round_trip_empties_the_outbox() {
    let db = Db::new();
    let kept = capture(&db.store, "Kept");
    let refused = capture(&db.store, "Refused");

    let batch = db.store.push_batch(100).unwrap().unwrap();
    assert_eq!(batch.count, 2);

    let body: Value = serde_json::from_str(&batch.body).unwrap();
    let commands = body["commands"].as_array().unwrap();
    assert_eq!(commands[0]["entity"], "task");
    assert_eq!(commands[0]["entity_id"], kept.to_string());
    assert_eq!(commands[0]["op"], "insert");
    assert_eq!(commands[1]["entity_id"], refused.to_string());

    let response = json!({ "results": [
        { "id": commands[0]["id"], "status": "applied" },
        { "id": commands[1]["id"], "status": "rejected", "reason": "invalid" }
    ]});
    let summary = db.store.record_push(response.to_string()).unwrap();
    assert_eq!(
        (summary.answered, summary.accepted, summary.rejected),
        (2, 1, 1)
    );

    assert!(db.store.push_batch(100).unwrap().is_none());
    let rejections = db.store.rejections(true).unwrap();
    assert_eq!(rejections.len(), 1);
    assert_eq!(rejections[0].entity_id, refused.to_string());
    assert_eq!(rejections[0].reason, "invalid");
    // A rejection asks for a snapshot.
    assert_eq!(db.store.pull_cursor().unwrap(), None);
}

#[test]
fn a_pull_brings_rows_and_the_cursor() {
    let db = Db::new();
    let id = Uuid::now_v7();
    let rows = json!({ "task": [task_row(id, "From the server")] });

    let summary = db.store.apply_pull(pull_body("u1", rows)).unwrap();
    assert_eq!(summary.cursor, 7);
    assert!(!summary.more);
    assert_eq!(db.store.pull_cursor().unwrap(), Some(7));

    let task = db.store.task(id).unwrap().unwrap();
    assert_eq!(task.title, "From the server");
    assert_eq!(task.dates.planned_at, Some(at("2026-10-20T07:00:00Z")));
    assert_eq!(task.inserted_at, Some(at("2026-10-01T08:00:00Z")));
    assert_eq!(db.store.status().unwrap().user_id.as_deref(), Some("u1"));
}

#[test]
fn a_pull_for_another_account_changes_nothing() {
    let db = Db::new();
    db.store.apply_pull(pull_body("u1", json!({}))).unwrap();

    let rows = json!({ "task": [task_row(Uuid::now_v7(), "Not mine")] });
    let error = db.store.apply_pull(pull_body("u2", rows)).unwrap_err();
    assert!(matches!(error, StoreError::OtherAccount));
    assert!(db.store.tasks(TaskFilter::All).unwrap().is_empty());
}

#[test]
fn a_body_that_is_not_the_sync_api_is_a_storage_error() {
    let db = Db::new();
    let error = db.store.apply_pull("{}".into()).unwrap_err();
    assert!(matches!(error, StoreError::Storage { .. }));
}

#[test]
fn a_closed_store_refuses_every_call() {
    let db = Db::new();
    db.store.close();
    assert!(matches!(db.store.status(), Err(StoreError::Closed)));
    assert!(matches!(
        db.store.add_task(NewTask {
            title: "Late".into(),
            ..NewTask::default()
        }),
        Err(StoreError::Closed)
    ));
}

#[test]
fn another_connection_sees_a_write() {
    let db = Db::new();
    let widget = Store::open(db.path.to_string_lossy().into_owned()).unwrap();
    let before = db.store.data_version().unwrap();

    capture(&widget, "From the widget");

    assert_ne!(db.store.data_version().unwrap(), before);
    assert_eq!(db.store.tasks(TaskFilter::Inbox).unwrap().len(), 1);
    widget.close();
}

#[test]
fn the_agenda_carries_the_time_each_task_is_on_it_for() {
    let db = Db::new();
    let add = |title: &str, planned: Option<&str>, due: Option<&str>| {
        db.store
            .add_task(NewTask {
                title: title.into(),
                planned_at: planned.map(at),
                due_at: due.map(at),
                ..NewTask::default()
            })
            .unwrap()
    };
    let report = add(
        "Report",
        Some("2020-05-04T07:00:00Z"),
        Some("2020-05-04T15:00:00Z"),
    );
    let call = add("Call", Some("2020-05-04T10:00:00Z"), None);
    add("Later", Some("2020-05-05T07:00:00Z"), None);

    let agenda = db.store.agenda(at("2020-05-04T22:00:00Z")).unwrap();
    let entries: Vec<(Uuid, Timestamp, bool)> =
        agenda.iter().map(|e| (e.task.id, e.at, e.due)).collect();
    assert_eq!(
        entries,
        [
            (call, at("2020-05-04T10:00:00Z"), false),
            (report, at("2020-05-04T15:00:00Z"), true),
        ]
    );
}

#[test]
fn a_day_takes_the_fields_default_time_in_the_zone() {
    let day = LocalDate {
        year: 2026,
        month: 9,
        day: 30,
    };
    let zone = || "Europe/Copenhagen".to_string();

    assert_eq!(
        local_instant(day, None, DateField::Due, zone()).unwrap(),
        at("2026-09-30T15:00:00Z")
    );
    let two_thirty = LocalTime {
        hour: 14,
        minute: 30,
    };
    assert_eq!(
        local_instant(day, Some(two_thirty), DateField::Due, zone()).unwrap(),
        at("2026-09-30T12:30:00Z")
    );
    assert_eq!(
        default_time(DateField::Planned),
        LocalTime { hour: 9, minute: 0 }
    );
}

#[test]
fn an_unknown_zone_or_day_is_invalid() {
    let day = LocalDate {
        year: 2026,
        month: 2,
        day: 30,
    };
    assert!(matches!(
        local_instant(day, None, DateField::Due, "Europe/Copenhagen".into()),
        Err(StoreError::Invalid { .. })
    ));
    let day = LocalDate { day: 3, ..day };
    assert!(matches!(
        local_instant(day, None, DateField::Due, "Mars/Olympus".into()),
        Err(StoreError::Invalid { .. })
    ));
}
