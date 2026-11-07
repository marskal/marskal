// A web page or link as an inbox task (ADR 0035). Pure, so Node can test it.

import type { TaskFields } from "@marskal/webext-common/command";
import { NOTES_MAX, URL_MAX, cleanTitle, fit, length } from "@marskal/webext-common/text";

const CUT_MARK = "\n\n[Cut to fit.]";

// The server refuses these (`Marskal.Url`, ADR 0022).
const REFUSED = new Set(["javascript:", "data:", "vbscript:"]);

export interface Page {
  title: string;
  url: string;
  /** Text selected on the page, or null to leave it out. */
  selection: string | null;
}

export interface Link {
  /** The link's text, where the browser gives it. */
  text: string | null;
  url: string;
  /** The address of the page the link is on. */
  pageUrl: string | null;
}

export function pageFields(page: Page): TaskFields {
  const address = placeUrl(page.url);
  const quote = page.selection ? quoted(page.selection) : "";
  return {
    title: cleanTitle(page.title) || titleFromUrl(page.url),
    url: address.url,
    notes: fit(join(address.note, quote), NOTES_MAX, CUT_MARK),
    inbox: true,
  };
}

export function linkFields(link: Link): TaskFields {
  const address = placeUrl(link.url);
  const from = link.pageUrl && usable(link.pageUrl) ? `Linked from <${link.pageUrl}>` : "";
  return {
    title: cleanTitle(link.text ?? "") || titleFromUrl(link.url),
    url: address.url,
    notes: fit(join(address.note, from), NOTES_MAX, CUT_MARK),
    inbox: true,
  };
}

/**
 * Where an address goes: the task's URL when the server takes it; the notes
 * when it is only too long; nowhere when its scheme is refused.
 */
export function placeUrl(url: string): { url: string | null; note: string } {
  if (!usable(url)) return { url: null, note: "" };
  if (length(url) > URL_MAX) return { url: null, note: url };
  return { url, note: "" };
}

/** The selection as a Markdown block quote. */
export function quoted(text: string): string {
  return text
    .replace(/\r\n?/g, "\n")
    .trim()
    .split("\n")
    .map((line) => (line.trim() ? `> ${line.trim()}` : ">"))
    .join("\n");
}

function usable(url: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  return !REFUSED.has(parsed.protocol) && !/\s/.test(url);
}

function titleFromUrl(url: string): string {
  return usable(url) ? cleanTitle(url) : "Web page";
}

function join(...parts: string[]): string {
  return parts.filter(Boolean).join("\n\n");
}
