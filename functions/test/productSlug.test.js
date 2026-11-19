const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const { baseSlug, sizeSlug, stableSuffix, slugCandidates, planSlugs, SLUG_MAX } = require("../catalog/productSlug");

describe("baseSlug", () => {
  test("lowercase ASCII, hyphenated, cut at a word boundary", () => {
    const s = baseSlug("Wi-Fi Signal Antenna Main Board Connector Motherboard Flex Cable For Samsung Note 10 Plus Lite / Note 20 Ultra");
    assert.equal(s, "wi-fi-signal-antenna-main-board-connector-motherboard-flex");
    assert.ok(s.length <= SLUG_MAX);
    assert.match(s, /^[a-z0-9]+(-[a-z0-9]+)*$/);
  });

  test("'+' is 'plus' only inside a model name", () => {
    assert.equal(baseSlug("100%Working For iPhone 11+Face ID Mainboard"), "iphone-11-face-id-mainboard");
    assert.equal(baseSlug("Samsung Galaxy S21+ Case"), "samsung-galaxy-s21-plus-case");
    assert.equal(baseSlug("Note 10+ / S21+ LCD"), "note-10-plus-s21-plus-lcd");
    assert.equal(baseSlug("Galaxy Note 10 Plus Battery"), "galaxy-note-10-plus-battery");
  });

  test("marketing filler is dropped", () => {
    assert.equal(baseSlug("AAA+++ OLED Screen 100% Original Genuine Hot Sale New Arrival Fast Shipping"), "oled-screen");
    assert.equal(baseSlug("Fully Tested 100% Working Motherboard For iPhone 8"), "motherboard-for-iphone-8");
    assert.equal(baseSlug("Radhuni Pure Mustard Oil - 100% Natural"), "radhuni-pure-mustard-oil-100-percent-natural");
  });

  test("source and supplier words never appear", () => {
    const s = baseSlug("AliExpress China Choice Cainiao Wireless Charger");
    assert.equal(s, "choice-wireless-charger");
  });

  test("inch marks and decimals", () => {
    assert.equal(baseSlug("6.3'' Mate 20 Lite Display"), "6-3-inch-mate-20-lite-display");
    assert.equal(baseSlug('6.8" Super AMOLED'), "6-8-inch-super-amoled");
  });

  test("Bangla is spelled out, units become abbreviations", () => {
    assert.equal(baseSlug("রাঁধুনী সরিষার তেল ৫০০ মিলি"), "randhuni-sorishar-tel-500-ml");
    assert.equal(baseSlug("প্রাণ মসুর ডাল (দেশি) - ১ কেজি"), "pran-mosur-dal-deshi-1-kg");
    assert.equal(baseSlug("চাল ৫কেজি"), "chal-5-kg");
    assert.equal(baseSlug("সয়াবিন তেল ২ লিটার"), "soyabin-tel-2-l");
    assert.equal(baseSlug("ডিম ১২ পিস"), "dim-12-pcs");
    assert.equal(baseSlug("চিনি ৫০০ গ্রাম"), "chini-500-g");
  });

  test("never empty, never starts/ends on filler words", () => {
    assert.equal(baseSlug("✨✨"), "product");
    assert.equal(baseSlug("For the iPhone with"), "iphone");
  });
});

describe("sizeSlug", () => {
  test("normalizes the size field", () => {
    assert.equal(sizeSlug("1 ltr"), "1-ltr");
    assert.equal(sizeSlug("400 ml"), "400ml");
    assert.equal(sizeSlug("500gm"), "500g");
    assert.equal(sizeSlug("300 gm"), "300g");
    assert.equal(sizeSlug("500 MG"), "500mg");
    assert.equal(sizeSlug("1.5 Litre"), "1-5-ltr");
    assert.equal(sizeSlug("4 pcs/1 hali"), "4pcs");
    assert.equal(sizeSlug("১ কেজি"), "1kg");
    assert.equal(sizeSlug("Each"), "");
    assert.equal(sizeSlug(""), "");
  });
});

describe("planSlugs", () => {
  test("same title, different sizes: every member gets its size", () => {
    const plan = planSlugs([
      { id: "a", name: "Coca-Cola Soft Drink", strength: "1 ltr" },
      { id: "b", name: "Coca-Cola Soft Drink", strength: "400 ml" },
    ]);
    assert.equal(plan.get("a").slug, "coca-cola-soft-drink-1-ltr");
    assert.equal(plan.get("b").slug, "coca-cola-soft-drink-400ml");
  });

  test("same title, no or equal size: fixed suffix", () => {
    const plan = planSlugs([
      { id: "a", name: "Phone Case", strength: "" },
      { id: "b", name: "Phone Case", strength: "" },
    ]);
    assert.equal(plan.get("a").slug, `phone-case-${stableSuffix("a")}`);
    assert.equal(plan.get("b").slug, `phone-case-${stableSuffix("b")}`);
  });

  test("names that differ after 60 characters keep the difference", () => {
    const head = "Fully Tested Authentic Motherboard For iPhone 11 Pro Max 64g/256g Unlocked Mainboard";
    const plan = planSlugs([
      { id: "a", name: `${head} With Face ID Cleaned iCloud` },
      { id: "b", name: `${head} Without Face ID Clean iCloud` },
    ]);
    assert.match(plan.get("a").slug, /-with-face-id$/);
    assert.match(plan.get("b").slug, /-without-face-id$/);
  });

  test("all unique, all within the limit, taken slugs avoided", () => {
    const plan = planSlugs([{ id: "a", name: "Vim Bar", strength: "" }], new Set(["vim-bar"]));
    assert.notEqual(plan.get("a").slug, "vim-bar");
    assert.ok(plan.get("a").slug.startsWith("vim-bar"));
  });

  test("stable: same input, same output", () => {
    const products = [{ id: "x1", name: "Same", strength: "" }, { id: "x2", name: "Same", strength: "" }];
    assert.deepEqual([...planSlugs(products)], [...planSlugs([...products].reverse())]);
  });
});

describe("slugCandidates", () => {
  test("name first, then size, then suffix; all within the limit", () => {
    const list = slugCandidates({ name: "Vim Dishwashing Bar", strength: "300 gm" }, "doc1");
    assert.equal(list[0], "vim-dishwashing-bar");
    assert.ok(list.includes("vim-dishwashing-bar-300g"));
    assert.ok(list.includes(`vim-dishwashing-bar-300g-${stableSuffix("doc1")}`));
    assert.ok(list.every((s) => s.length <= SLUG_MAX + 20));
  });
});

describe("slugCandidates with a taken title", () => {
  test("never offers the bare name; size first", () => {
    const list = slugCandidates({ name: "Vim Dishwashing Bar", strength: "300 gm" }, "doc9", { titleTaken: true });
    assert.equal(list[0], "vim-dishwashing-bar-300g");
    assert.ok(!list.includes("vim-dishwashing-bar"));
  });
});

describe("planSlugs: one extra word", () => {
  test("the name with the extra word gets it, the other keeps the plain slug", () => {
    const plan = planSlugs([
      { id: "imp", name: '6.8" Super AMOLED For Samsung S21 Ultra 5G G998 G998U Display Touch Screen Digitizer For Samsung S21Ultra G998B LCD' },
      { id: "own", name: '6.8" Super AMOLED For Samsung S21 Ultra 5G G998 G998U Display Touch Screen For Samsung S21Ultra G998B LCD' },
    ]);
    assert.match(plan.get("imp").slug, /-digitizer$/);
    assert.equal(plan.get("own").slug, "6-8-inch-super-amoled-for-samsung-s21-ultra-5g-g998-g998u");
  });
});
