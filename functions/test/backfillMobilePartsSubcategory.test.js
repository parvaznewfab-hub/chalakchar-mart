const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  classifyByTitle,
  SUBCATEGORY_MOTHERBOARD,
  SUBCATEGORY_DISPLAY,
} = require("../scripts/backfillMobilePartsSubcategory");

describe("classifyByTitle (pure keyword match, no Firestore)", () => {
  test("motherboard/mainboard/logic board titles classify as Motherboard & Mainboard", () => {
    const titles = [
      "Unlocked Mainboard Fully Tested 100% Working Motherboard Compatible With 12 Mini",
      "Fully Tested Motherboard For iPhone 7/7 Plus/8/8 Plus 32g/128g/64g/256g",
      "Fully Tested Working Well Motherboard For iPhone 11 Pro Max With/Without Face ID Cleaned iCloud And Support Update Logic Board",
      "Damaged Motherboard For iPhone X XR XS 11 12 13 14 15 16 Pro Max Logic Board Without Nand",
    ];
    for (const title of titles) {
      assert.equal(classifyByTitle(title), SUBCATEGORY_MOTHERBOARD, title);
    }
  });

  test("display/digitizer/lcd/amoled titles classify as Display & Digitizer", () => {
    const titles = [
      '6.8" Super AMOLED For Samsung S21 Ultra 5G G998 G998U Display Touch Screen Digitizer For Samsung S21Ultra G998B LCD',
      "Replacement OLED Display Screen for iPhone 13",
      "LCD Touch Screen Digitizer Assembly",
    ];
    for (const title of titles) {
      assert.equal(classifyByTitle(title), SUBCATEGORY_DISPLAY, title);
    }
  });

  test("titles matching neither keyword group return null (left unmatched, never guessed)", () => {
    const titles = [
      "USB-C Fast Charging Cable 1m",
      "Bluetooth Wireless Earbuds",
      "",
      null,
      undefined,
    ];
    for (const title of titles) {
      assert.equal(classifyByTitle(title), null, String(title));
    }
  });

  test("motherboard/mainboard takes precedence when a title mentions both groups", () => {
    assert.equal(
      classifyByTitle("Motherboard with LCD test fixture display"),
      SUBCATEGORY_MOTHERBOARD
    );
  });
});
