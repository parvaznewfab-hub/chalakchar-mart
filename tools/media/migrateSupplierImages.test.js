// Run: node --test tools/media/migrateSupplierImages.test.js  (after `npm install` in tools/media)
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { supplierUrlsOf, imageFieldChanges, isSupplierUrl, keyFor } = require("./migrateSupplierImages");

const A = "https://ae01.alicdn.com/kf/Sabc.jpg";
const B = "https://ae-pic-a1.aliexpress-media.com/kf/Sdef.jpg";
const OWN = "https://firebasestorage.googleapis.com/v0/b/x/o/products%2Fa.jpg?alt=media";

test("finds supplier images in every field, ignores our own", () => {
  const p = {
    image: A, imageUrl: A, images: [A, OWN],
    variants: [{ id: "v_0", image: B }, { id: "v_1", image: OWN }],
    overviewHtml: `<p>x</p><img src="${B}"><img src='//ae01.alicdn.com/kf/Sghi.png'>`,
  };
  assert.deepEqual(supplierUrlsOf(p).sort(), [A, B, "//ae01.alicdn.com/kf/Sghi.png"].sort());
  assert.equal(isSupplierUrl(OWN), false);
  assert.equal(isSupplierUrl("https://evil.com/alicdn.com/x.jpg"), false);
});

test("rewrites every use of a mapped URL, nothing else", () => {
  const map = new Map([[A, "NEW_A"], [B, "NEW_B"]]);
  const p = { image: A, images: [A, OWN], variants: [{ id: "v_0", image: B, price: 5 }], overviewHtml: `<img src="${B}" alt="b">` };
  const c = imageFieldChanges(p, map);
  assert.deepEqual(c, {
    image: "NEW_A",
    images: ["NEW_A", OWN],
    variants: [{ id: "v_0", image: "NEW_B", price: 5 }],
    overviewHtml: '<img src="NEW_B" alt="b">',
  });
  assert.deepEqual(imageFieldChanges({ image: OWN }, map), {});
});

test("storage keys are neutral and stable", () => {
  assert.match(keyFor(A), /^[0-9a-f]{24}$/);
  assert.equal(keyFor(A), keyFor(A));
  assert.equal(keyFor("//ae01.alicdn.com/kf/Sabc.jpg"), keyFor(A));
});
