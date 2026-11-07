// Task field limits and text helpers both extensions share. Pure, so Node
// can test them.

/** The server's limits, in characters (`Marskal.Tasks.Task`, ADR 0022). */
export const TITLE_MAX = 500;
export const NOTES_MAX = 32_768;
export const URL_MAX = 2048;

/** Collapses runs of whitespace, trims, and cuts to the title limit. */
export function cleanTitle(text: string): string {
  return clip(text.replace(/\s+/g, " ").trim(), TITLE_MAX);
}

/**
 * `text` cut to `max` characters, ending with `mark` when it was cut, so
 * the result still fits.
 */
export function fit(text: string, max: number, mark: string): string {
  if (length(text) <= max) return text;
  return clip(text, max - length(mark)).trimEnd() + mark;
}

// Postgres counts code points, so these do too.
export function length(text: string): number {
  return Array.from(text).length;
}

export function clip(text: string, max: number): string {
  const chars = Array.from(text);
  return chars.length <= max ? text : chars.slice(0, max).join("");
}

export function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
