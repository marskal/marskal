// A message as an inbox task (ADR 0024). Pure, so Node can test it.

/** The server's limits, in characters (`Marskal.Tasks.Task`, ADR 0022). */
export const TITLE_MAX = 500;
export const NOTES_MAX = 32_768;
export const URL_MAX = 2048;

const CUT_MARK = "\n\n[Cut to fit; the rest is in the message.]";

export interface Mail {
  subject: string;
  author: string;
  date: Date;
  headerMessageId: string;
  /** The readable text, or null to leave it out of the notes. */
  text: string | null;
}

export interface TaskFields {
  title: string;
  notes: string;
  url: string | null;
  inbox: true;
}

export interface TextPart {
  contentType: string;
  content: string;
}

export function taskFields(mail: Mail, formatDate: (date: Date) => string = localDate): TaskFields {
  return {
    title: title(mail),
    notes: notes(mail, formatDate),
    url: messageUrl(mail.headerMessageId),
    inbox: true,
  };
}

export function title(mail: Pick<Mail, "subject" | "author">): string {
  const subject = mail.subject.replace(/\s+/g, " ").trim();
  if (subject) return clip(subject, TITLE_MAX);

  const sender = senderName(mail.author);
  return clip(sender ? `Mail from ${sender}` : "Mail", TITLE_MAX);
}

/** A `mid:` URL (RFC 2392) for a Message-ID without its angle brackets. */
export function messageUrl(headerMessageId: string): string | null {
  const id = headerMessageId.trim().replace(/^<|>$/g, "");
  if (!id) return null;

  const url = `mid:${encodeURIComponent(id).replaceAll("%40", "@")}`;
  return url.length <= URL_MAX ? url : null;
}

/** The display name of `Name <address>`, or the address. */
export function senderName(author: string): string {
  const match = author.match(/^\s*"?(.*?)"?\s*<([^>]*)>\s*$/);
  if (!match) return author.trim();
  return match[1]!.trim() || match[2]!.trim();
}

function notes(mail: Mail, formatDate: (date: Date) => string): string {
  const head = [`From: ${mail.author.trim()}`, `Date: ${formatDate(mail.date)}`].join("  \n");
  const text = mail.text?.trim();
  if (!text) return head;

  const whole = `${head}\n\n${text}`;
  if (length(whole) <= NOTES_MAX) return whole;

  return clip(whole, NOTES_MAX - length(CUT_MARK)).trimEnd() + CUT_MARK;
}

/**
 * The readable text of a message's inline parts: its plain-text parts, or
 * its HTML parts converted when there are none.
 */
export async function messageText(
  parts: TextPart[],
  toPlainText: (html: string) => Promise<string>,
): Promise<string | null> {
  const plain = parts.filter((part) => part.contentType === "text/plain");
  const texts =
    plain.length > 0
      ? plain.map((part) => part.content)
      : await Promise.all(
          parts.filter((part) => part.contentType === "text/html").map((part) => toPlainText(part.content)),
        );

  const text = texts
    .map((t) => t.replace(/\r\n?/g, "\n").trim())
    .filter(Boolean)
    .join("\n\n");
  return text || null;
}

function localDate(date: Date): string {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
}

// Postgres counts code points; a code point never splits a grapheme count
// the server would see as larger.
function length(text: string): number {
  return Array.from(text).length;
}

function clip(text: string, max: number): string {
  const chars = Array.from(text);
  return chars.length <= max ? text : chars.slice(0, max).join("");
}
