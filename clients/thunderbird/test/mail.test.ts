import assert from "node:assert/strict";
import { test } from "node:test";
import {
  NOTES_MAX,
  TITLE_MAX,
  messageText,
  messageUrl,
  senderName,
  taskFields,
  title,
  type Mail,
} from "../src/mail.ts";

const mail: Mail = {
  subject: "Invoice  for\tOctober",
  author: "Ada Lovelace <ada@example.com>",
  date: new Date("2026-10-08T09:30:00Z"),
  headerMessageId: "abc.123@mail.example.com",
  text: "Please pay by Friday.\n",
};

const isoDate = (date: Date) => date.toISOString();

test("a message becomes an inbox task", () => {
  assert.deepEqual(taskFields(mail, isoDate), {
    title: "Invoice for October",
    notes: "From: Ada Lovelace <ada@example.com>  \nDate: 2026-10-08T09:30:00.000Z\n\nPlease pay by Friday.",
    url: "mid:abc.123@mail.example.com",
    inbox: true,
  });
});

test("without text the notes are the sender and date", () => {
  assert.equal(
    taskFields({ ...mail, text: null }, isoDate).notes,
    "From: Ada Lovelace <ada@example.com>  \nDate: 2026-10-08T09:30:00.000Z",
  );
});

test("a message without a subject is titled by its sender", () => {
  assert.equal(title({ subject: "  ", author: "Ada Lovelace <ada@example.com>" }), "Mail from Ada Lovelace");
  assert.equal(title({ subject: "", author: "<ada@example.com>" }), "Mail from ada@example.com");
  assert.equal(title({ subject: "", author: "" }), "Mail");
});

test("a long subject is cut to the title limit, by code point", () => {
  const long = "🦀".repeat(TITLE_MAX + 10);
  assert.equal(Array.from(title({ subject: long, author: "" })).length, TITLE_MAX);
});

test("long text is cut to the notes limit and says so", () => {
  const notes = taskFields({ ...mail, text: "x".repeat(NOTES_MAX * 2) }, isoDate).notes;
  assert.equal(notes.length, NOTES_MAX);
  assert.match(notes, /\[Cut to fit; the rest is in the message\.\]$/);
});

test("Message-IDs become mid: URLs", () => {
  assert.equal(messageUrl("<a b/c@x.y>"), "mid:a%20b%2Fc@x.y");
  assert.equal(messageUrl(""), null);
  assert.equal(messageUrl("x".repeat(3000)), null);
});

test("sender names", () => {
  assert.equal(senderName('"Lovelace, Ada" <ada@example.com>'), "Lovelace, Ada");
  assert.equal(senderName("ada@example.com"), "ada@example.com");
});

test("plain text is preferred to HTML", async () => {
  const convert = async (html: string) => `converted ${html}`;

  assert.equal(
    await messageText(
      [
        { contentType: "text/html", content: "<p>Hi</p>" },
        { contentType: "text/plain", content: "Hi\r\nthere" },
      ],
      convert,
    ),
    "Hi\nthere",
  );
  assert.equal(await messageText([{ contentType: "text/html", content: "<p>Hi</p>" }], convert), "converted <p>Hi</p>");
  assert.equal(await messageText([], convert), null);
});
