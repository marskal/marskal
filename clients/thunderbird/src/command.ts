// Push commands and their results (ADR 0019). The extension only inserts
// inbox tasks, so it needs nothing of the client library (ADR 0024).

import { v7 as uuidv7 } from "uuid";
import type { TaskFields } from "./mail.ts";

export interface Command {
  id: string;
  entity: "task";
  entity_id: string;
  op: "insert";
  fields: TaskFields;
  at: string;
}

export interface PushResult {
  id: string;
  status: "applied" | "noop" | "replayed" | "rejected";
  reason?: string;
  errors?: Record<string, unknown>;
}

export interface Outcome {
  added: number;
  problems: string[];
}

export function insertCommand(fields: TaskFields, now: Date = new Date()): Command {
  return {
    id: uuidv7(),
    entity: "task",
    entity_id: uuidv7(),
    op: "insert",
    fields,
    at: now.toISOString(),
  };
}

/**
 * What came of `commands`. A command without a result was not applied: the
 * server stopped before it.
 */
export function outcome(commands: Command[], results: PushResult[]): Outcome {
  const byId = new Map(results.map((result) => [result.id, result]));
  const problems: string[] = [];
  let added = 0;

  for (const command of commands) {
    const result = byId.get(command.id);
    const title = command.fields.title;

    if (!result) {
      problems.push(`“${title}” was not added; the server stopped first.`);
    } else if (result.status === "rejected") {
      problems.push(`“${title}” was refused: ${rejection(result)}.`);
    } else {
      added += 1;
    }
  }

  return { added, problems };
}

function rejection(result: PushResult): string {
  const errors = Object.entries(result.errors ?? {}).flatMap(([field, messages]) =>
    Array.isArray(messages) ? messages.map((message) => `${field} ${message}`) : [],
  );
  return errors.length > 0 ? errors.join(", ") : (result.reason ?? "no reason given");
}
