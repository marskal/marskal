// The signed-in account: the server and its tokens, in the extension's local
// storage. Every page and the background script share it, so a refresh
// takes a lock: the refresh token rotates, and using a spent one signs the
// device out (ADR 0021).

import { Api, ApiError, type TokenResponse } from "./api.ts";
import { outcome, type Command, type Outcome } from "./command.ts";

export interface Account {
  server: string;
  accessToken: string;
  refreshToken: string;
  /** Milliseconds since the epoch. */
  expiresAt: number;
}

export class SignedOut extends Error {
  constructor() {
    super("Sign in from the extension's options first.");
  }
}

const KEY = "account";
const LOCK = "marskal-account";
// Refresh a little early, so a token does not expire on the way.
const MARGIN_MS = 60_000;

export async function account(): Promise<Account | null> {
  const stored = await messenger.storage.local.get(KEY);
  return (stored[KEY] as Account | undefined) ?? null;
}

export async function signIn(server: string, tokens: TokenResponse): Promise<void> {
  await messenger.storage.local.set({ [KEY]: fromResponse(server, tokens) });
}

/** Revokes the device at the server, if it can, and forgets the tokens. */
export async function signOut(): Promise<void> {
  await navigator.locks.request(LOCK, async () => {
    const current = await account();
    if (!current) return;
    try {
      await new Api(current.server).revoke(current.refreshToken);
    } finally {
      await messenger.storage.local.remove(KEY);
    }
  });
}

/**
 * Pushes `commands`. Refreshes the access token when it is about to expire,
 * or when the server no longer takes it.
 */
export async function push(commands: Command[]): Promise<Outcome> {
  let current = await fresh(false);
  const api = new Api(current.server);

  try {
    return outcome(commands, await api.push(current.accessToken, commands));
  } catch (error) {
    if (!(error instanceof ApiError && error.kind === "unauthorized")) throw error;
    current = await fresh(true);
    return outcome(commands, await api.push(current.accessToken, commands));
  }
}

function fresh(force: boolean): Promise<Account> {
  return navigator.locks.request(LOCK, async () => {
    // Read inside the lock: another page may just have refreshed.
    const current = await account();
    if (!current) throw new SignedOut();
    if (!force && current.expiresAt - MARGIN_MS > Date.now()) return current;

    let tokens: TokenResponse;
    try {
      tokens = await new Api(current.server).refresh(current.refreshToken);
    } catch (error) {
      if (error instanceof ApiError && (error.code === "invalid_grant" || error.kind === "unauthorized")) {
        await messenger.storage.local.remove(KEY);
        throw new SignedOut();
      }
      throw error;
    }

    const next = fromResponse(current.server, tokens);
    await messenger.storage.local.set({ [KEY]: next });
    return next;
  });
}

function fromResponse(server: string, tokens: TokenResponse): Account {
  return {
    server,
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token,
    expiresAt: Date.now() + tokens.expires_in * 1000,
  };
}
