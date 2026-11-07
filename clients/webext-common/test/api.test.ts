import assert from "node:assert/strict";
import { test } from "node:test";
import { ApiError, hostPattern, requireHttps, serverUrl } from "../src/api.ts";

test("server URLs keep only the origin", () => {
  assert.equal(serverUrl(" https://marskal.localhost:8275/ "), "https://marskal.localhost:8275");
  assert.equal(serverUrl("https://tasks.marskal.example/settings?x=1"), "https://tasks.marskal.example");
  assert.equal(serverUrl("ftp://tasks.marskal.example"), null);
  assert.equal(serverUrl("tasks.marskal.example"), null);
});

test("an http server URL becomes https", () => {
  assert.equal(serverUrl("http://tasks.marskal.example/"), "https://tasks.marskal.example");
});

test("host permissions leave out the port", () => {
  assert.equal(hostPattern("https://marskal.localhost:8275"), "https://marskal.localhost/*");
  assert.equal(hostPattern("https://tasks.marskal.example"), "https://tasks.marskal.example/*");
});

test("OAuth endpoints must be HTTPS", () => {
  const endpoints = {
    device_authorization_endpoint: "https://tasks.marskal.example/oauth2/device/auth",
    token_endpoint: "https://tasks.marskal.example/oauth2/token",
    revocation_endpoint: "https://tasks.marskal.example/oauth2/revoke",
  };
  assert.equal(requireHttps(endpoints), endpoints);
  assert.throws(
    () => requireHttps({ ...endpoints, token_endpoint: "http://tasks.marskal.example/oauth2/token" }),
    ApiError,
  );
});
