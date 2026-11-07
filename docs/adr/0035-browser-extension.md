# 0035. Browser extension

## Status

Accepted

A capture-only client, like the Thunderbird extension of
[ADR 0024](0024-thunderbird-extension.md), whose sign-in, writing, and
limits it follows unless this record says otherwise.

## Context

Much work starts as a web page: an article to read, an issue to answer, a
form to fill in. Capturing it today means copying the address into the
inbox by hand. Tasks already carry one URL ([ADR 0022](0022-task-and-project-url.md)),
so a page fits one task.

Firefox and the Chromium browsers (Chrome, Edge, Brave, Vivaldi) run the
same Manifest V3 extensions, with small differences: Chromium runs the
background as a service worker and draws PNG icons only, and Firefox keeps
a background script and has its own add-on ID and data-collection
declaration. Safari runs them too, but only inside a native app built with
Xcode.

The Thunderbird extension already holds everything but reading the
message: signing in, the token refresh, the push, the options page.

## Decision

An extension in **`clients/browser`**, Manifest V3, for **Firefox** and
**Chromium** from one source. The build writes `dist/firefox` and
`dist/chromium`, each with its own manifest. Firefox back to the **oldest
supported ESR**, now 140, as for Thunderbird; Chromium from **120**.
TypeScript, built to plain JavaScript; its own `devenv.nix` with Node.
Safari is left for later.

It is listed as **Marskal** on addons.mozilla.org, ID
`browser@marskal.app`, which never changes, and on the Chrome Web Store.
The listing text and privacy policy are in `LISTING.md` beside it.

### Shared code

What the two extensions share moves to **`clients/webext-common`**: the
account and token refresh, the OAuth and push calls, the options page's
sign-in, the field limits, the stylesheet and logo. Each extension links
it as `file:../webext-common` and bundles it. It has **no runtime
dependencies**: an extension passes its own UUIDv7 generator, so nothing
needs installing there for an extension to build. It is not a published
package. A store that rebuilds from source gets both folders.

### What it does

- The **toolbar button** opens a popup: the title, editable, prefilled with
  the page's title; when text is selected on the page, whether to keep it in
  the notes; and **Add to inbox**.
- **"Add page to Marskal inbox"** in the page's context menu, and with
  text selected, adds the page with no popup. **"Add link to Marskal
  inbox"** on a link adds the page it leads to. Both report with a
  notification.
- Each becomes one task in the **inbox** (`inbox = true`, ADR 0017):

  | Field | Page | Link |
  |-------|------|------|
  | `title` | The page's title, trimmed, at most 500 characters; without one, the address | The link's text where the browser gives it (Firefox); else the address |
  | `url` | The page's address | The link's address |
  | `notes` | The selected text, quoted | "Linked from" and the page's address |

  An address the server refuses (`javascript:`, `data:`, `vbscript:`) is
  left out. One longer than 2048 characters goes in the notes instead, so it
  is not lost. Notes are cut to fit the notes limit.

### Permissions

- `activeTab` and `scripting`: the button and the context menu give the
  extension that one tab, for its title, its address, and the selected
  text. It cannot see other tabs, or a tab before it is asked to.
- `contextMenus`, `notifications`, `storage`.
- The server's host only, asked for when signing in, as for Thunderbird.

### Sign-in

As ADR 0024, with its own public Hydra client,
**`marskal-browser-extension`**, scopes `offline_access sync:write`. The
verification page opens in a new tab. Tokens are kept in the extension's
local storage, in the browser profile.

### Writing

As ADR 0024: one `insert` per page, ids made by the extension, the popup's
**Try again** sending the same ids. In Chromium the context-menu push runs
in the service worker, which the browser keeps alive while it waits.

## Consequences

- One more OAuth client file on the server. Its consent page shows
  "Marskal browser extension" and that it can only write.
- `clients/thunderbird` now depends on `clients/webext-common`; a change
  there is tested in both extensions. The Thunderbird source archive holds
  both folders.
- The extension sees a page only when the user adds it. Pages a browser
  keeps extensions out of (its settings, the web stores) can still be added
  from the button, with title and address but never the selected text.
- Firefox for Android runs extensions but has no context menu; the popup
  may work there, untested. Safari needs a native wrapper app and its own
  listing, and can reuse `dist/chromium`.
- Tests: the page-to-task and link-to-task mapping (no title, long title,
  refused and long addresses, selection quoted and cut), in Node's test
  runner; the push and sign-in are tested in `clients/webext-common`.
