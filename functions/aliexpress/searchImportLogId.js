// -----------------------------------------------------------------------------
// searchImportLog/{docId} for a search query (dedupe + 24h result cache).
//
// The id used to be the ASCII slug of the query, so a Bangla query slugged to
// nothing and fell back to the literal "query": every all-Bangla search
// shared ONE log doc (live: "১২৮ জিবি এসএসডি এর দাম কত? ..." -> "query"), and
// for 24h each later Bangla search was answered "already_done" with that
// first search's products. A query with any non-ASCII text now gets a short
// hash of its full text appended (or is only the hash when no ASCII is left),
// so different queries never share a doc. Pure-ASCII ids are unchanged.
// -----------------------------------------------------------------------------

const crypto = require("crypto");

function asciiSlug(value) {
  return String(value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function searchImportLogDocId(query) {
  const text = String(query ?? "").trim().toLowerCase().replace(/\s+/g, " ");
  const slug = asciiSlug(text);
  // eslint-disable-next-line no-control-regex
  if (!/[^\x00-\x7F]/.test(text)) return slug || "query";
  const hash = crypto.createHash("sha1").update(text).digest("hex").slice(0, 12);
  return slug ? `${slug.slice(0, 100)}_${hash}` : `q_${hash}`;
}

module.exports = { searchImportLogDocId };
