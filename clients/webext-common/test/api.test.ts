import assert from "node:assert/strict";
import { test } from "node:test";
import { Api, ApiError, hostPattern, requireHttps, serverUrl } from "../src/api.ts";

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

test("a push names the client, and a 426 says which version the server needs", async () => {
  const scope = globalThis as { browser?: unknown; fetch: typeof fetch };
  const realFetch = scope.fetch;
  let sent: Headers | null = null;
  scope.browser = { runtime: { getManifest: () => ({ version: "0.3.0" }) } };
  scope.fetch = async (_url, init) => {
    sent = new Headers(init?.headers);
    return new Response(JSON.stringify({ error: "client_outdated", minimum_version: "0.4.0" }), { status: 426 });
  };

  try {
    await assert.rejects(new Api("https://tasks.marskal.example", "marskal-thunderbird").push("token", []), (error) => {
      assert.ok(error instanceof ApiError);
      assert.equal(error.kind, "outdated");
      assert.equal(error.code, "0.4.0");
      assert.match(error.message, /0\.4\.0 or later/);
      return true;
    });
    assert.equal(sent!.get("marskal-client"), "marskal-thunderbird/0.3.0");
  } finally {
    scope.fetch = realFetch;
    delete scope.browser;
  }
});
