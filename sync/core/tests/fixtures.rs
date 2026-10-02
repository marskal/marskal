//! The shared vectors in `sync/fixtures`, which the server runs too
//! (ADR 0018).

use marskal_sync::ids::{LinkKind, link_id};
use marskal_sync::rank;
use serde_json::Value;
use uuid::Uuid;

fn read(name: &str) -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../fixtures")
        .join(name);
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

#[test]
fn rank_json() {
    let vectors = read("rank.json");

    for case in vectors["between"].as_array().unwrap() {
        let before = case["before"].as_str();
        let later = case["later"].as_str();
        assert_eq!(
            rank::between(before, later).as_deref(),
            case["rank"].as_str(),
            "between({before:?}, {later:?})"
        );
    }

    for case in vectors["valid"].as_array().unwrap() {
        let rank_text = case["rank"].as_str().unwrap();
        assert_eq!(
            rank::is_valid(rank_text),
            case["valid"].as_bool().unwrap(),
            "{rank_text:?}"
        );
    }

    for case in vectors["spread"].as_array().unwrap() {
        let expected: Vec<&str> = case["ranks"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| r.as_str().unwrap())
            .collect();
        assert_eq!(rank::spread(case["count"].as_u64().unwrap()), expected);
    }
}

#[test]
fn link_ids_json() {
    for case in read("link_ids.json")["links"].as_array().unwrap() {
        let kind = if case["kind"] == "task" {
            LinkKind::Task
        } else {
            LinkKind::Project
        };
        let owner = Uuid::parse_str(case["owner_id"].as_str().unwrap()).unwrap();
        let tag = Uuid::parse_str(case["tag_id"].as_str().unwrap()).unwrap();
        assert_eq!(
            link_id(kind, owner, tag).to_string(),
            case["id"].as_str().unwrap()
        );
    }
}
