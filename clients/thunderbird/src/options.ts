// Sign in and out (ADR 0024). The device grant, as for the terminal
// (ADR 0021): show a code, open the browser, poll until the user allows it.

import { account, signIn, signOut } from "./account.ts";
import { Api, ApiError, hostPattern, serverUrl } from "./api.ts";
import { describeError } from "./capture.ts";

const signedOutView = document.querySelector<HTMLFormElement>("#signed-out")!;
const serverInput = document.querySelector<HTMLInputElement>("#server")!;
const signInButton = document.querySelector<HTMLButtonElement>("#sign-in")!;
const pendingView = document.querySelector<HTMLElement>("#pending")!;
const userCode = document.querySelector<HTMLElement>("#user-code")!;
const verificationLink = document.querySelector<HTMLAnchorElement>("#verification")!;
const cancelButton = document.querySelector<HTMLButtonElement>("#cancel")!;
const signedInView = document.querySelector<HTMLElement>("#signed-in")!;
const signedInServer = document.querySelector<HTMLElement>("#signed-in-server")!;
const signOutButton = document.querySelector<HTMLButtonElement>("#sign-out")!;
const status = document.querySelector<HTMLParagraphElement>("#status")!;

// Bumped to stop a sign-in that is polling.
let attempt = 0;

signedOutView.addEventListener("submit", (event) => {
  event.preventDefault();

  const server = serverUrl(serverInput.value);
  if (!server) {
    show("Enter the server’s address, such as https://tasks.marskal.example.");
    return;
  }
  // Shows an http address as the https one that is used.
  serverInput.value = server;

  // Asked for before anything is awaited: Thunderbird grants permissions
  // only while handling the click.
  const granted = messenger.permissions.request({ origins: [hostPattern(server)] });
  void begin(server, granted);
});

cancelButton.addEventListener("click", () => {
  attempt += 1;
  pendingView.hidden = true;
  signInButton.disabled = false;
  show("");
  void render();
});

signOutButton.addEventListener("click", () => {
  signOutButton.disabled = true;
  void signOut()
    .catch((error: unknown) => show(`Signed out here; the server was not told: ${describeError(error)}`))
    .finally(() => {
      signOutButton.disabled = false;
      void render();
    });
});

messenger.storage.onChanged.addListener(() => void render());
void render();

async function render(): Promise<void> {
  const current = await account();
  signedInView.hidden = !current;
  signedOutView.hidden = !!current || !pendingView.hidden;
  if (current) {
    signedInServer.textContent = current.server;
    pendingView.hidden = true;
  }
}

async function begin(server: string, granted: Promise<boolean>): Promise<void> {
  if (!(await granted)) {
    show("Thunderbird needs access to the server to add tasks.");
    return;
  }

  const thisAttempt = ++attempt;
  const api = new Api(server);
  signInButton.disabled = true;
  show("");

  try {
    const device = await api.deviceCode();
    const link = device.verification_uri_complete ?? device.verification_uri;

    userCode.textContent = device.user_code;
    verificationLink.href = link;
    verificationLink.textContent = device.verification_uri;
    signedOutView.hidden = true;
    pendingView.hidden = false;
    await messenger.windows.openDefaultBrowser(link);

    const deadline = Date.now() + device.expires_in * 1000;
    let interval = Math.max(device.interval, 1);

    while (thisAttempt === attempt) {
      await sleep(interval * 1000);
      if (thisAttempt !== attempt) return;
      if (Date.now() > deadline) throw new Error("The code expired. Sign in again.");

      try {
        await signIn(server, await api.pollToken(device.device_code));
        show("");
        return;
      } catch (error) {
        if (!(error instanceof ApiError && error.kind === "oauth")) throw error;
        if (error.code === "authorization_pending") continue;
        if (error.code === "slow_down") {
          interval += 5;
          continue;
        }
        if (error.code === "access_denied") throw new Error("Sign-in was denied.");
        if (error.code === "expired_token") throw new Error("The code expired. Sign in again.");
        throw error;
      }
    }
  } catch (error) {
    if (thisAttempt === attempt) show(describeError(error));
  } finally {
    if (thisAttempt === attempt) {
      pendingView.hidden = true;
      signInButton.disabled = false;
      await render();
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function show(text: string): void {
  status.textContent = text;
}
