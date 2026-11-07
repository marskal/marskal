// Sign in and out (ADR 0024). The verification page opens in the default
// browser.

import { startOptions } from "@marskal/webext-common/options";
import { CLIENT_ID } from "./client.ts";

startOptions({
  clientId: CLIENT_ID,
  app: "Thunderbird",
  openLink: (url) => messenger.windows.openDefaultBrowser(url),
});
