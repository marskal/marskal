//! The shared vectors in `core/fixtures` that need a replica: tag search
//! runs over stored tags (ADR 0039).

use marskal_replica::{PullResponse, PullUser, Store};
use serde_json::Value;
use std::collections::BTreeMap;

fn read(name: &str) -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../fixtures")
        .join(name);
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

#[test]
fn path_search_json_tags() {
    let tags = &read("path_search.json")["tags"];
    let rows = tags["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|row| {
            let mut row = row.as_object().unwrap().clone();
            row.insert("merged_into_id".into(), Value::Null);
            row.insert("discarded_at".into(), Value::Null);
            row
        })
        .collect();
    let mut store = Store::open_in_memory().unwrap();
    store
        .apply_pull(&PullResponse {
            cursor: 1,
            snapshot: true,
            more: false,
            user: PullUser {
                id: "u1".into(),
                timezone: "Europe/Copenhagen".into(),
            },
            rows: BTreeMap::from([("tag".to_string(), rows)]),
            gone: vec![],
        })
        .unwrap();
    let world = store.world().unwrap();
    let limit = tags["limit"].as_u64().unwrap() as usize;

    for case in tags["search"].as_array().unwrap() {
        let query = case["query"].as_str().unwrap();
        let paths: Vec<Vec<String>> = world
            .search_tags(query, limit)
            .into_iter()
            .map(|tag| world.tag_path(tag.id))
            .collect();
        let expected: Vec<Vec<String>> = serde_json::from_value(case["paths"].clone()).unwrap();
        assert_eq!(paths, expected, "{query:?}");
    }
}
