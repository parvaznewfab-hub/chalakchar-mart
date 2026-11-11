#!/usr/bin/env node
// Writes test/fixtures/category_normalize_parity.json from the JS
// normalizeCategoryKey/slugifyCategoryName, so the Dart port in
// lib/utils/category_normalize.dart can be checked against the real
// backend output. Re-run after changing either side:
//   node functions/scripts/generateCategoryNormalizeParityFixture.js
// Read-only with respect to Firestore: no network, no writes besides the
// fixture file.

const fs = require("fs");
const path = require("path");
const { normalizeCategoryKey, slugifyCategoryName } = require("../category/categoryNormalize");

// Inputs are built from explicit code points (cp) so review can see exactly
// which form each case uses: precomposed and decomposed Bangla nukta
// letters render identically.
const cp = (...points) => String.fromCodePoint(...points);
const NUKTA = 0x09bc;
const PARTS_BN = "পার্টস ও আনুষাঙ্গিক "; // contains no nukta letters

const inputs = [
  // Precomposed nukta letters
  { label: "precomposed YYA U+09DF", input: cp(0x09df) },
  { label: "precomposed RRA U+09DC", input: cp(0x09dc) },
  { label: "precomposed RHA U+09DD", input: cp(0x09dd) },
  // Decomposed forms: base + NUKTA U+09BC
  { label: "decomposed YA U+09AF + NUKTA", input: cp(0x09af, NUKTA) },
  { label: "decomposed DDA U+09A1 + NUKTA", input: cp(0x09a1, NUKTA) },
  { label: "decomposed DDHA U+09A2 + NUKTA", input: cp(0x09a2, NUKTA) },
  { label: "word with precomposed YYA", input: PARTS_BN + cp(0x09df) },
  { label: "word with decomposed YYA", input: PARTS_BN + cp(0x09af, NUKTA) },
  { label: "BORO (ব+ড়) precomposed", input: cp(0x09ac, 0x09dc) },
  { label: "BORO (ব+ড়) decomposed", input: cp(0x09ac, 0x09a1, NUKTA) },
  { label: "ASHARH (আষাঢ়) precomposed", input: cp(0x0986, 0x09b7, 0x09be, 0x09dd) },
  { label: "ASHARH (আষাঢ়) decomposed", input: cp(0x0986, 0x09b7, 0x09be, 0x09a2, NUKTA) },
  // Full-width Latin (U+FF21..)
  { label: "full-width MOBILE PARTS", input: cp(0xff2d, 0xff2f, 0xff22, 0xff29, 0xff2c, 0xff25, 0x20, 0xff30, 0xff21, 0xff32, 0xff34, 0xff33) },
  { label: "full-width LCD & 4K", input: cp(0xff2c, 0xff23, 0xff24, 0x20, 0xff06, 0x20, 0xff14, 0xff2b) },
  { label: "ideographic space U+3000 between words", input: "Mobile" + cp(0x3000) + "Parts" },
  // Whitespace
  { label: "leading/trailing/internal spaces", input: "   Display   &    Digitizer   " },
  { label: "tabs and newlines", input: cp(0x09) + "Motherboard " + cp(0x0a) + "& " + cp(0x09) + " Mainboard" + cp(0x0a) },
  { label: "non-breaking spaces U+00A0", input: cp(0xa0) + "Mobile" + cp(0xa0, 0xa0) + "Parts" + cp(0xa0) },
  // Mixed Bangla + English
  { label: "mixed Bangla+English", input: "Mobile Parts (মোবাইল পার্টস)" },
  { label: "mixed with case + spaces", input: "  SAMSUNG   ডিসপ্লে  & Touch  " },
  { label: "mixed full-width + decomposed nukta", input: cp(0xff2c, 0xff23, 0xff24, 0x20, 0x09ac, 0x09a1, NUKTA) + " Display" },
  { label: "mixed Bangla with precomposed nukta + English", input: "  Mobile  " + cp(0x09ac, 0x09dc) + "  Display  " },
  // Edge cases
  { label: "empty", input: "" },
  { label: "only spaces", input: "    " },
];

const cases = inputs.map(({ label, input }) => ({
  label,
  input,
  normalized: normalizeCategoryKey(input),
  slug: slugifyCategoryName(input),
}));

const out = path.join(__dirname, "..", "..", "test", "fixtures", "category_normalize_parity.json");
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify({ generatedBy: "functions/category/categoryNormalize.js", cases }, null, 2) + "\n");
console.log(`wrote ${cases.length} cases to ${out}`);
