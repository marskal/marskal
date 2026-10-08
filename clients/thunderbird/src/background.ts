// "Add to Marskal inbox" in the message list's context menu: every selected
// message becomes an inbox task, with no popup (ADR 0024).

import { push, SignedOut } from "./account.ts";
import { allMessages, describeError, readMessage } from "./capture.ts";
import { insertCommand } from "./command.ts";

const MENU_ID = "add-to-inbox";
// The push takes at most 1000 commands (ADR 0019).
const MAX_MESSAGES = 1000;

messenger.runtime.onInstalled.addListener(() => {
  messenger.menus.create({ id: MENU_ID, title: "Add to Marskal inbox", contexts: ["message_list"] });
});

messenger.menus.onClicked.addListener((info) => {
  if (info.menuItemId !== MENU_ID || !info.selectedMessages) return;
  void addSelected(info.selectedMessages);
});

async function addSelected(list: messenger.MessageList): Promise<void> {
  try {
    const messages = await allMessages(list);
    if (messages.length > MAX_MESSAGES) {
      await notify(`Select at most ${MAX_MESSAGES} messages at a time.`);
      return;
    }

    const commands = await Promise.all(
      messages.map(async (message) => insertCommand(await readMessage(message, true))),
    );
    const { added, problems } = await push(commands);

    const summary = added === 1 ? "Added 1 message to the inbox." : `Added ${added} messages to the inbox.`;
    await notify([summary, ...problems].join("\n"));
  } catch (error) {
    await notify(describeError(error));
    if (error instanceof SignedOut) await messenger.runtime.openOptionsPage();
  }
}

function notify(message: string): Promise<string> {
  return messenger.notifications.create({ type: "basic", title: "Marskal", message, iconUrl: "icon.svg" });
}
