// Reads a message from Thunderbird into task fields (ADR 0024).

import { messageText, taskFields, type TaskFields } from "./mail.ts";

export async function readMessage(message: messenger.MessageHeader, withText: boolean): Promise<TaskFields> {
  const text = withText
    ? await messageText(await messenger.messages.listInlineTextParts(message.id), (html) =>
        messenger.messengerUtilities.convertToPlainText(html),
      )
    : null;

  return taskFields({
    subject: message.subject,
    author: message.author,
    date: message.date,
    headerMessageId: message.headerMessageId,
    text,
  });
}

/** Every message of a list, following its pages. */
export async function allMessages(list: messenger.MessageList): Promise<messenger.MessageHeader[]> {
  const messages = [...list.messages];
  let id = list.id;
  while (id) {
    const page = await messenger.messages.continueList(id);
    messages.push(...page.messages);
    id = page.id;
  }
  return messages;
}

export function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
