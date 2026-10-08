import assert from "node:assert/strict";
import { test } from "node:test";
import { insertCommand, outcome } from "../src/command.ts";
import type { TaskFields } from "../src/mail.ts";

const fields = (title: string): TaskFields => ({ title, notes: "", url: null, inbox: true });

test("an insert command has fresh UUIDv7 ids and the time", () => {
  const command = insertCommand(fields("Milk"), new Date("2026-10-08T09:30:00Z"));

  assert.equal(command.entity, "task");
  assert.equal(command.op, "insert");
  assert.equal(command.at, "2026-10-08T09:30:00.000Z");
  assert.match(command.id, /^[0-9a-f]{8}-[0-9a-f]{4}-7/);
  assert.match(command.entity_id, /^[0-9a-f]{8}-[0-9a-f]{4}-7/);
  assert.notEqual(command.id, command.entity_id);
});

test("applied, noop, and replayed commands count as added", () => {
  const commands = ["A", "B", "C"].map((title) => insertCommand(fields(title)));
  const results = commands.map((command, i) => ({
    id: command.id,
    status: (["applied", "noop", "replayed"] as const)[i]!,
  }));

  assert.deepEqual(outcome(commands, results), { added: 3, problems: [] });
});

test("rejected and missing commands are problems", () => {
  const [a, b, c] = ["A", "B", "C"].map((title) => insertCommand(fields(title)));

  assert.deepEqual(
    outcome(
      [a!, b!, c!],
      [
        { id: a!.id, status: "applied" },
        { id: b!.id, status: "rejected", reason: "invalid", errors: { title: ["can't be blank"] } },
      ],
    ),
    {
      added: 1,
      problems: ["“B” was refused: title can't be blank.", "“C” was not added; the server stopped first."],
    },
  );
});

test("a rejection without field errors gives its reason", () => {
  const command = insertCommand(fields("A"));
  assert.deepEqual(outcome([command], [{ id: command.id, status: "rejected", reason: "not_found" }]).problems, [
    "“A” was refused: not_found.",
  ]);
});
