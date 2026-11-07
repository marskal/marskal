// HTTP to the server: OAuth through Ory Hydra (ADR 0021) and the sync push
// (ADR 0019). Only the server's URL is configured; the OAuth endpoints come
// from its metadata (RFC 8414).

import type { Command, PushResult } from "./command.ts";

/** This program's OAuth client (ADR 0024). */
export const CLIENT_ID = "marskal-thunderbird";

/** It never pulls, so it does not ask to read (ADR 0024). */
export const SCOPE = "offline_access sync:write";

export type ApiErrorKind = "unauthorized" | "forbidden" | "oauth" | "http" | "network";

export class ApiError extends Error {
  kind: ApiErrorKind;
  /** The OAuth error code, such as `authorization_pending`. */
  code: string | null;

  constructor(kind: ApiErrorKind, message: string, code: string | null = null) {
    super(message);
    this.kind = kind;
    this.code = code;
  }
}

export interface DeviceCode {
  device_code: string;
  user_code: string;
  verification_uri: string;
  verification_uri_complete?: string;
  expires_in: number;
  interval: number;
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

export interface Endpoints {
  device_authorization_endpoint: string;
  token_endpoint: string;
  revocation_endpoint: string;
}

/**
 * The server's URL as entered, without a trailing slash, path, query, or
 * fragment. Mail goes only over HTTPS, so an http address becomes https.
 * Null when it is not a web address.
 */
export function serverUrl(input: string): string | null {
  let url: URL;
  try {
    url = new URL(input.trim());
  } catch {
    return null;
  }
  if (url.protocol === "http:") url.protocol = "https:";
  if (url.protocol !== "https:") return null;
  return url.origin;
}

/**
 * The host permission for a server. Without the port: Thunderbird, like
 * Firefox, does not apply a match pattern that has one.
 */
export function hostPattern(server: string): string {
  const url = new URL(server);
  return `${url.protocol}//${url.hostname}/*`;
}

export class Api {
  server: string;
  #endpoints: Promise<Endpoints> | null = null;

  constructor(server: string) {
    this.server = server;
  }

  deviceCode(): Promise<DeviceCode> {
    return this.#form("device_authorization_endpoint", { client_id: CLIENT_ID, scope: SCOPE });
  }

  pollToken(deviceCode: string): Promise<TokenResponse> {
    return this.#form("token_endpoint", {
      grant_type: "urn:ietf:params:oauth:grant-type:device_code",
      client_id: CLIENT_ID,
      device_code: deviceCode,
    });
  }

  refresh(refreshToken: string): Promise<TokenResponse> {
    return this.#form("token_endpoint", {
      grant_type: "refresh_token",
      client_id: CLIENT_ID,
      refresh_token: refreshToken,
    });
  }

  /** Revokes a token and its chain (RFC 7009). */
  async revoke(token: string): Promise<void> {
    const endpoints = await this.#metadata();
    const response = await send(endpoints.revocation_endpoint, {
      method: "POST",
      body: new URLSearchParams({ client_id: CLIENT_ID, token }),
    });
    if (!response.ok) throw new ApiError("http", `The server answered ${response.status}.`);
  }

  async push(accessToken: string, commands: Command[]): Promise<PushResult[]> {
    const response = await send(`${this.server}/api/v1/sync/push`, {
      method: "POST",
      headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
      body: JSON.stringify({ commands }),
    });
    const body = await json<{ results: PushResult[] }>(response);
    return body.results;
  }

  #metadata(): Promise<Endpoints> {
    this.#endpoints ??= send(`${this.server}/.well-known/oauth-authorization-server`, {})
      .then((response) => json<Endpoints>(response))
      .then(requireHttps)
      .catch((error: unknown) => {
        this.#endpoints = null;
        throw error;
      });
    return this.#endpoints;
  }

  async #form<T>(endpoint: keyof Endpoints, fields: Record<string, string>): Promise<T> {
    const endpoints = await this.#metadata();
    const response = await send(endpoints[endpoint], { method: "POST", body: new URLSearchParams(fields) });
    return json<T>(response);
  }
}

/** Tokens go only over HTTPS, wherever the metadata points. */
export function requireHttps(endpoints: Endpoints): Endpoints {
  const used = [endpoints.device_authorization_endpoint, endpoints.token_endpoint, endpoints.revocation_endpoint];
  for (const url of used) {
    if (!url?.startsWith("https://")) {
      throw new ApiError("http", `The server named an endpoint that is not HTTPS: ${url}`);
    }
  }
  return endpoints;
}

async function send(url: string, init: RequestInit): Promise<Response> {
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(30_000) });
  } catch (error) {
    throw new ApiError("network", `Could not reach the server: ${(error as Error).message}`);
  }
}

async function json<T>(response: Response): Promise<T> {
  const text = await response.text();
  let body: unknown = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    // Not JSON; the status says what happened.
  }

  if (response.ok && body !== null) return body as T;

  const code = (body as { error?: unknown } | null)?.error;
  if (response.status === 401) throw new ApiError("unauthorized", "The server did not accept the sign-in.");
  if (response.status === 403) throw new ApiError("forbidden", "This device is not allowed to add tasks.");
  if (response.status === 400 && typeof code === "string") {
    throw new ApiError("oauth", `The server said ${code}.`, code);
  }
  throw new ApiError("http", `The server answered ${response.status}.`);
}
