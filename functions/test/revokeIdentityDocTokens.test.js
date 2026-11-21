const test = require("node:test");
const assert = require("node:assert/strict");
const { tokenCount, filesFromPrivateDocs } = require("../scripts/revokeIdentityDocTokens");

test("token count from Storage metadata", () => {
  assert.equal(tokenCount({}), 0);
  assert.equal(tokenCount({ metadata: {} }), 0);
  assert.equal(tokenCount({ metadata: { firebaseStorageDownloadTokens: "" } }), 0);
  assert.equal(tokenCount({ metadata: { firebaseStorageDownloadTokens: "a" } }), 1);
  assert.equal(tokenCount({ metadata: { firebaseStorageDownloadTokens: "a,b" } }), 2);
});

test("files come only from the private docs' *Path fields inside the owner's folder", () => {
  const { files, skipped } = filesFromPrivateDocs([
    { kind: "vendor", id: "v1", data: {
      nidFrontPath: "vendors/v1/documents/f.jpeg", nidBackPath: "", tradeLicensePath: "vendors/v2/documents/t.jpeg",
      nidFront: "https://x/link", phone: "017",
    } },
    { kind: "rider", id: "r1", data: { nidFrontPath: "delivery_partner_documents/r1/f.jpg", nidBackPath: "delivery_partner_documents/r1/b.jpg" } },
    { kind: "rider", id: "r2", data: {} },
  ]);
  assert.deepEqual(files.map((f) => f.path), [
    "vendors/v1/documents/f.jpeg", "delivery_partner_documents/r1/f.jpg", "delivery_partner_documents/r1/b.jpg",
  ]);
  assert.deepEqual(skipped, [{ kind: "vendor", id: "v1", which: "tradeLicense" }]);
});
