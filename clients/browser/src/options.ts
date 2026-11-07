// Sign in and out (ADR 0035). The verification page opens in a new tab.

import { startOptions } from "@marskal/webext-common/options";
import { api, CLIENT_ID } from "./browser.ts";

startOptions({
  clientId: CLIENT_ID,
  app: "The browser",
  openLink: (url) => api.tabs.create({ url }),
});
