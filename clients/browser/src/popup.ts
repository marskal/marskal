// The toolbar button's popup: check the title, then add the page to the
// inbox (ADR 0035).

import { account, push, SignedOut } from "@marskal/webext-common/account";
import { insertCommand, type Command } from "@marskal/webext-common/command";
import { cleanTitle, describeError } from "@marskal/webext-common/text";
import { v7 as uuidv7 } from "uuid";
import { api, CLIENT_ID, selectionIn, type Tab } from "./browser.ts";
import { pageFields } from "./page.ts";

const form = document.querySelector<HTMLFormElement>("#capture")!;
const titleInput = document.querySelector<HTMLInputElement>("#title")!;
const selectionLabel = document.querySelector<HTMLLabelElement>("#with-selection-label")!;
const withSelection = document.querySelector<HTMLInputElement>("#with-selection")!;
const submit = document.querySelector<HTMLButtonElement>("#submit")!;
const status = document.querySelector<HTMLParagraphElement>("#status")!;
const signIn = document.querySelector<HTMLButtonElement>("#sign-in")!;

let tab: Tab | null = null;
let selection: string | null = null;
// Kept after the first try, so trying again sends the same ids and a push
// the server did get is replayed, not doubled (ADR 0024).
let command: Command | null = null;

signIn.addEventListener("click", () => {
  void api.runtime.openOptionsPage().then(() => window.close());
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

  [tab = null] = await api.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url) {
    show("This tab has no page to add.");
    return;
  }

  selection = await selectionIn(tab);
  selectionLabel.hidden = !selection;
  titleInput.value = pageFields({ title: tab.title ?? "", url: tab.url, selection: null }).title;
  form.hidden = false;
  titleInput.select();
}

async function add(): Promise<void> {
  if (!tab?.url) return;
  setBusy(true);

  try {
    if (!command) {
      const fields = pageFields({
        title: tab.title ?? "",
        url: tab.url,
        selection: withSelection.checked ? selection : null,
      });
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
  withSelection.disabled = busy || command !== null;
  if (busy) show("Adding…");
}

function show(text: string): void {
  status.textContent = text;
}
