// Push commands and their results (ADR 0019). A capture extension only
// inserts inbox tasks, so it needs nothing of the client library (ADR 0024).

/** An inbox task as an extension sends it. */
export interface TaskFields {
  title: string;
  notes: string;
  url: string | null;
  inbox: true;
}

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

/**
 * An insert of `fields`, with a new command id and task id from `newId`, a
 * UUIDv7 generator. The extension passes its own, so this package has no
 * dependencies of its own to install.
 */
export function insertCommand(fields: TaskFields, newId: () => string, now: Date = new Date()): Command {
  return {
    id: newId(),
    entity: "task",
    entity_id: newId(),
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
