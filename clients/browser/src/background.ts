// The context menu: add the page, or a link on it, to the inbox with no
// popup, and report with a notification (ADR 0035). In Chromium this is a
// service worker, so every listener is added at the top level.

import { push, SignedOut } from "@marskal/webext-common/account";
import { insertCommand, type TaskFields } from "@marskal/webext-common/command";
import { describeError } from "@marskal/webext-common/text";
import { v7 as uuidv7 } from "uuid";
import { api, CLIENT_ID, type MenuClick, type Tab } from "./browser.ts";
import { linkFields, pageFields } from "./page.ts";

const ADD_PAGE = "add-page";
const ADD_LINK = "add-link";

// Also run on an update, when the menu may still be there.
api.runtime.onInstalled.addListener(async () => {
  await api.contextMenus.removeAll();
  api.contextMenus.create({ id: ADD_PAGE, title: "Add page to Marskal inbox", contexts: ["page", "selection"] });
  api.contextMenus.create({ id: ADD_LINK, title: "Add link to Marskal inbox", contexts: ["link"] });
});

api.contextMenus.onClicked.addListener((info, tab) => {
  const fields = menuFields(info, tab);
  if (fields) void add(fields);
});

function menuFields(info: MenuClick, tab: Tab | undefined): TaskFields | null {
  if (info.menuItemId === ADD_LINK && info.linkUrl) {
    return linkFields({ text: info.linkText ?? null, url: info.linkUrl, pageUrl: info.pageUrl ?? tab?.url ?? null });
  }
  const url = tab?.url ?? info.pageUrl;
  if (info.menuItemId === ADD_PAGE && url) {
    return pageFields({ title: tab?.title ?? "", url, selection: info.selectionText ?? null });
  }
  return null;
}

async function add(fields: TaskFields): Promise<void> {
  try {
    const { added, problems } = await push(CLIENT_ID, [insertCommand(fields, uuidv7)]);
    await notify(added === 1 ? `Added “${fields.title}” to the inbox.` : problems.join("\n"));
  } catch (error) {
    await notify(describeError(error));
    if (error instanceof SignedOut) await api.runtime.openOptionsPage();
  }
}

function notify(message: string): Promise<string> {
  return api.notifications.create({ type: "basic", title: "Marskal", message, iconUrl: "icon-128.png" });
}
