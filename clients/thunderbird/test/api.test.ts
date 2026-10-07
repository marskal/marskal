import assert from "node:assert/strict";
import { test } from "node:test";
import { hostPattern, serverUrl } from "../src/api.ts";

test("server URLs keep only the origin", () => {
  assert.equal(serverUrl(" http://marskal.localhost:8275/ "), "http://marskal.localhost:8275");
  assert.equal(serverUrl("https://tasks.example.com/settings?x=1"), "https://tasks.example.com");
  assert.equal(serverUrl("ftp://tasks.example.com"), null);
  assert.equal(serverUrl("tasks.example.com"), null);
});

test("host permissions leave out the port", () => {
  assert.equal(hostPattern("http://marskal.localhost:8275"), "http://marskal.localhost/*");
  assert.equal(hostPattern("https://tasks.example.com"), "https://tasks.example.com/*");
});
