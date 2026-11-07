// The part of the WebExtension API the shared code uses. Thunderbird and
// Firefox name it `browser`, Chromium `chrome`; in Manifest V3 both return
// promises.

export interface Storage {
  get(keys: string | string[]): Promise<Record<string, unknown>>;
  set(items: Record<string, unknown>): Promise<void>;
  remove(keys: string | string[]): Promise<void>;
}

export interface Ext {
  storage: {
    local: Storage;
    onChanged: { addListener(listener: (changes: Record<string, unknown>, area: string) => void): void };
  };
  permissions: {
    request(permissions: { origins: string[] }): Promise<boolean>;
  };
  runtime: {
    openOptionsPage(): Promise<void>;
  };
}

const scope = globalThis as { browser?: Ext; chrome?: Ext };

/** The extension API, looked up when first used, so Node can load this. */
export function ext(): Ext {
  const api = scope.browser ?? scope.chrome;
  if (!api) throw new Error("Not running as an extension.");
  return api;
}
