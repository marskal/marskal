import assert from "node:assert/strict";
import { test } from "node:test";
import { TITLE_MAX, cleanTitle, fit, length } from "../src/text.ts";

test("titles collapse whitespace and are cut by code point", () => {
  assert.equal(cleanTitle("  Invoice\tfor \n October "), "Invoice for October");
  assert.equal(length(cleanTitle("🦀".repeat(TITLE_MAX + 10))), TITLE_MAX);
});

test("fit leaves short text alone and marks a cut", () => {
  assert.equal(fit("short", 10, " [cut]"), "short");
  assert.equal(fit("a long piece of text", 12, " [cut]"), "a long [cut]");
  assert.equal(length(fit("x".repeat(100), 20, "…")), 20);
});
