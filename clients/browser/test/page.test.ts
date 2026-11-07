import assert from "node:assert/strict";
import { test } from "node:test";
import { NOTES_MAX, TITLE_MAX, URL_MAX } from "@marskal/webext-common/text";
import { linkFields, pageFields, placeUrl, quoted } from "../src/page.ts";

test("a page becomes an inbox task", () => {
  assert.deepEqual(
    pageFields({ title: "  Release\tnotes ", url: "https://marskal.example/notes", selection: null }),
    { title: "Release notes", url: "https://marskal.example/notes", notes: "", inbox: true },
  );
});

test("the selection is quoted in the notes", () => {
  const fields = pageFields({
    title: "Notes",
    url: "https://marskal.example/",
    selection: "First line\r\n\r\nSecond line  \n",
  });
  assert.equal(fields.notes, "> First line\n>\n> Second line");
});

test("a page without a title is titled by its address", () => {
  assert.equal(pageFields({ title: " ", url: "https://marskal.example/a", selection: null }).title, "https://marskal.example/a");
  assert.equal(pageFields({ title: "", url: "data:text/plain,hi", selection: null }).title, "Web page");
});

test("a long title is cut to the title limit", () => {
  const title = pageFields({ title: "x".repeat(TITLE_MAX * 2), url: "https://marskal.example/", selection: null }).title;
  assert.equal(title.length, TITLE_MAX);
});

test("refused schemes are left out", () => {
  for (const url of ["javascript:alert(1)", "data:text/html,<p>hi</p>", "VBScript:x", "not a url"]) {
    assert.deepEqual(placeUrl(url), { url: null, note: "" }, url);
  }
  assert.deepEqual(placeUrl("about:reader?url=x"), { url: "about:reader?url=x", note: "" });
});

test("an address over the URL limit goes in the notes", () => {
  const url = `https://marskal.example/?q=${"x".repeat(URL_MAX)}`;
  const fields = pageFields({ title: "Search", url, selection: "Hit" });
  assert.equal(fields.url, null);
  assert.equal(fields.notes, `${url}\n\n> Hit`);
});

test("a long selection is cut to the notes limit and says so", () => {
  const notes = pageFields({ title: "A", url: "https://marskal.example/", selection: "y".repeat(NOTES_MAX * 2) }).notes;
  assert.equal(notes.length, NOTES_MAX);
  assert.match(notes, /\[Cut to fit\.\]$/);
});

test("a link becomes a task for the page it leads to", () => {
  assert.deepEqual(
    linkFields({ text: "The spec", url: "https://marskal.example/spec", pageUrl: "https://marskal.example/blog" }),
    {
      title: "The spec",
      url: "https://marskal.example/spec",
      notes: "Linked from <https://marskal.example/blog>",
      inbox: true,
    },
  );
});

test("a link without text is titled by its address", () => {
  const fields = linkFields({ text: null, url: "https://marskal.example/spec", pageUrl: null });
  assert.equal(fields.title, "https://marskal.example/spec");
  assert.equal(fields.notes, "");
});

test("quoting keeps blank lines inside the quote", () => {
  assert.equal(quoted("\n a\n\n b \n"), "> a\n>\n> b");
});
