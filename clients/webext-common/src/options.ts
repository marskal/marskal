// Sign in and out (ADR 0024). The device grant, as for the terminal
// (ADR 0021): show a code, open the server's page, poll until the user
// allows it. Each extension's options page names its elements alike.

import { account, signIn, signOut } from "./account.ts";
import { Api, ApiError, hostPattern, serverUrl } from "./api.ts";
import { ext } from "./ext.ts";
import { describeError } from "./text.ts";

export interface OptionsConfig {
  /** The extension's OAuth client. */
  clientId: string;
  /** The program that asks for host access, as the user knows it. */
  app: string;
  /** Opens the verification page where the user can sign in. */
  openLink(url: string): Promise<unknown>;
}

export function startOptions(config: OptionsConfig): void {
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

    // Asked for before anything is awaited: permissions are granted only
    // while handling the click.
    const granted = ext().permissions.request({ origins: [hostPattern(server)] });
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
    void signOut(config.clientId)
      .catch((error: unknown) => show(`Signed out here; the server was not told: ${describeError(error)}`))
      .finally(() => {
        signOutButton.disabled = false;
        void render();
      });
  });

  ext().storage.onChanged.addListener(() => void render());
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
      show(`${config.app} needs access to the server to add tasks.`);
      return;
    }

    const thisAttempt = ++attempt;
    const api = new Api(server, config.clientId);
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
      await config.openLink(link);

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

  function show(text: string): void {
    status.textContent = text;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
