import assert from "node:assert/strict";
import { test } from "node:test";
import { hostPattern, serverUrl } from "../src/api.ts";

test("server URLs keep only the origin", () => {
  assert.equal(serverUrl(" http://marskal.localhost:8275/ "), "http://marskal.localhost:8275");
  assert.equal(serverUrl("https://tasks.marskal.example/settings?x=1"), "https://tasks.marskal.example");
  assert.equal(serverUrl("ftp://tasks.marskal.example"), null);
  assert.equal(serverUrl("tasks.marskal.example"), null);
});

test("host permissions leave out the port", () => {
  assert.equal(hostPattern("http://marskal.localhost:8275"), "http://marskal.localhost/*");
  assert.equal(hostPattern("https://tasks.marskal.example"), "https://tasks.marskal.example/*");
});
