// The part of the WebExtension API this extension uses beyond the shared
// code's, as both Firefox (`browser`) and Chromium (`chrome`) give it in
// Manifest V3.

export interface Tab {
  id?: number;
  title?: string;
  url?: string;
}

export interface MenuClick {
  menuItemId: string | number;
  selectionText?: string;
  linkUrl?: string;
  /** Firefox only. */
  linkText?: string;
  pageUrl?: string;
}

export interface Browser {
  tabs: {
    query(query: { active: true; currentWindow: true }): Promise<Tab[]>;
    create(properties: { url: string }): Promise<Tab>;
  };
  scripting: {
    executeScript<T>(injection: { target: { tabId: number }; func: () => T }): Promise<{ result?: T }[]>;
  };
  contextMenus: {
    create(properties: { id: string; title: string; contexts: string[] }): void;
    removeAll(): Promise<void>;
    onClicked: { addListener(listener: (info: MenuClick, tab?: Tab) => void): void };
  };
  notifications: {
    create(options: { type: "basic"; title: string; message: string; iconUrl: string }): Promise<string>;
  };
  runtime: {
    openOptionsPage(): Promise<void>;
    onInstalled: { addListener(listener: () => void): void };
  };
}

const scope = globalThis as { browser?: Browser; chrome?: Browser };

export const api: Browser = (scope.browser ?? scope.chrome)!;

/** This extension's OAuth client (ADR 0035). */
export const CLIENT_ID = "marskal-browser-extension";

/** The text selected in a tab, or null where the browser does not let us look. */
export async function selectionIn(tab: Tab): Promise<string | null> {
  if (tab.id === undefined) return null;
  try {
    const [frame] = await api.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => getSelection()?.toString() ?? "",
    });
    return frame?.result?.trim() || null;
  } catch {
    // The browser's own pages and the web stores refuse scripts.
    return null;
  }
}
