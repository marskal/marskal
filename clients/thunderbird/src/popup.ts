// The popup of the button on a displayed message: check the title, then add
// the message to the inbox (ADR 0024).

import { account, push, SignedOut } from "@marskal/webext-common/account";
import { insertCommand, type Command } from "@marskal/webext-common/command";
import { cleanTitle, describeError } from "@marskal/webext-common/text";
import { v7 as uuidv7 } from "uuid";
import { readMessage } from "./capture.ts";
import { CLIENT_ID } from "./client.ts";

const form = document.querySelector<HTMLFormElement>("#capture")!;
const titleInput = document.querySelector<HTMLInputElement>("#title")!;
const withText = document.querySelector<HTMLInputElement>("#with-text")!;
const submit = document.querySelector<HTMLButtonElement>("#submit")!;
const status = document.querySelector<HTMLParagraphElement>("#status")!;
const signIn = document.querySelector<HTMLButtonElement>("#sign-in")!;

let message: messenger.MessageHeader | null = null;
// Kept after the first try, so trying again sends the same ids and a push
// the server did get is replayed, not doubled (ADR 0024).
let command: Command | null = null;

signIn.addEventListener("click", () => {
  void messenger.runtime.openOptionsPage().then(() => window.close());
});

form.addEventListener("submit", (event) => {
  event.preventDefault();
  void add();
});

void start();

async function start(): Promise<void> {
  if (!(await account())) {
    show("Sign in to your Marskal server first.");
    signIn.hidden = false;
    return;
  }

  const [tab] = await messenger.tabs.query({ active: true, currentWindow: true });
  const { messages } = await messenger.messageDisplay.getDisplayedMessages(tab?.id);
  if (messages.length !== 1) {
    show("Select one message, or use “Add to Marskal inbox” in the message list’s menu.");
    return;
  }

  message = messages[0]!;
  const fields = await readMessage(message, false);
  titleInput.value = fields.title;
  form.hidden = false;
  titleInput.select();
}

async function add(): Promise<void> {
  if (!message) return;
  setBusy(true);

  try {
    if (!command) {
      const fields = await readMessage(message, withText.checked);
      const title = cleanTitle(titleInput.value);
      if (title) fields.title = title;
      command = insertCommand(fields, uuidv7);
    }

    const { added, problems } = await push(CLIENT_ID, [command]);
    if (added === 1) {
      show("Added to the inbox.");
      setTimeout(() => window.close(), 1200);
      return;
    }
    // Refused: trying again would be refused again.
    show(problems.join(" "));
  } catch (error) {
    if (error instanceof SignedOut) {
      show(describeError(error));
      signIn.hidden = false;
      return;
    }
    setBusy(false);
    show(describeError(error));
    if (command) submit.textContent = "Try again";
  }
}

function setBusy(busy: boolean): void {
  submit.disabled = busy;
  titleInput.disabled = busy || command !== null;
  withText.disabled = busy || command !== null;
  if (busy) show("Adding…");
}

function show(text: string): void {
  status.textContent = text;
}
