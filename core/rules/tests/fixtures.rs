//! The shared vectors in `core/fixtures`, which the server runs too
//! (ADR 0039).

use jiff::Timestamp;
use jiff::civil::{Date, Time};
use jiff::tz::TimeZone;
use marskal_rules::dates::{self, DateField};
use marskal_rules::ids::{LinkKind, link_id};
use marskal_rules::rank;
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

#[test]
fn dates_json() {
    for case in read("dates.json")["from_local"].as_array().unwrap() {
        let zone = TimeZone::get(case["zone"].as_str().unwrap()).unwrap();
        let date: Date = case["date"].as_str().unwrap().parse().unwrap();
        let time: Option<Time> = case["time"].as_str().map(|t| t.parse().unwrap());
        let field = match case["field"].as_str().unwrap() {
            "defer" => DateField::Defer,
            "planned" => DateField::Planned,
            _ => DateField::Due,
        };
        let expected: Timestamp = case["at"].as_str().unwrap().parse().unwrap();

        assert_eq!(
            dates::from_local(date, time, field, &zone),
            expected,
            "{} {} {:?}: {}",
            case["zone"],
            case["date"],
            case["time"],
            case["why"]
        );
    }
}
