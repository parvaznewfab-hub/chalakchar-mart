const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { matchCategoryByKeyword } = require("../category/aliExpressCategoryKeywords");

describe("matchCategoryByKeyword", () => {
  test("matches obvious electronics gadget titles", () => {
    assert.equal(
      matchCategoryByKeyword("Bone Conduction IPX5 Headphones Bluetooth 5.4 Waterproof Wireless Sports Headset"),
      "Electronics"
    );
    assert.equal(matchCategoryByKeyword("JBL WAVE 200TWS True Wireless Earbuds Bluetooth 5.0"), "Electronics");
  });

  test("Mobile Parts rules take priority over broader rules for repair-accessory titles", () => {
    assert.equal(matchCategoryByKeyword("iPhone 12 LCD Assembly Digitizer Replacement"), "Mobile Parts");
    assert.equal(matchCategoryByKeyword("Samsung Galaxy Motherboard Logic Board Repair Part"), "Mobile Parts");
  });

  test("Mobile Parts also catches phone repair TOOL kits (spudger/pry/disassembly + phone, any word order)", () => {
    assert.equal(
      matchCategoryByKeyword("10 Pcs Abs Plastic Spudger Disassembling Tools For Phone Cell Laptop Repair"),
      "Mobile Parts"
    );
    assert.equal(matchCategoryByKeyword("Phone Screen Opening Pry Tool Repair Kit"), "Mobile Parts");
    assert.equal(matchCategoryByKeyword("Professional Disassembly Tool Kit for Smartphone Repair"), "Mobile Parts");
  });

  test("the repair-tool-kit rule stays scoped to phone/mobile — unrelated repair kits never match", () => {
    assert.equal(matchCategoryByKeyword("Car Repair Tool Kit Socket Wrench Set"), null);
    assert.equal(matchCategoryByKeyword("Bicycle Repair Tool Kit Multi Tool"), null);
  });

  test("matches phone accessories distinctly from mobile parts", () => {
    assert.equal(matchCategoryByKeyword("Tempered Glass Screen Protector for iPhone 15"), "Mobile Accessories");
    assert.equal(matchCategoryByKeyword("Shockproof Phone Case with Popsocket Holder"), "Mobile Accessories");
  });

  test("matches watches, toys, jewellery", () => {
    assert.equal(matchCategoryByKeyword("Men's Smart Watch Fitness Tracker"), "Watches");
    assert.equal(matchCategoryByKeyword("Kids RC Car Remote Control Toy"), "Toys");
    assert.equal(matchCategoryByKeyword("18K Gold Plated Necklace Pendant"), "Jewellery");
  });

  test("is case-insensitive", () => {
    assert.equal(matchCategoryByKeyword("BLUETOOTH SPEAKER PORTABLE"), "Electronics");
  });

  test("returns null when nothing matches — never invents a category", () => {
    assert.equal(matchCategoryByKeyword("Danny Gen4 For V1 PK V2 high quality"), null);
    assert.equal(matchCategoryByKeyword(""), null);
    assert.equal(matchCategoryByKeyword(undefined), null);
  });
});
