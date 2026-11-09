const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  normalizeSearchImportQuery,
  validateSearchImportQuery,
} = require("../aliexpress/searchImportQueryGuard");

describe("normalizeSearchImportQuery", () => {
  test("trims and collapses whitespace, keeps case", () => {
    assert.equal(normalizeSearchImportQuery("  Redmi   Note 12\tDisplay "), "Redmi Note 12 Display");
  });

  test("null/undefined become empty", () => {
    assert.equal(normalizeSearchImportQuery(null), "");
    assert.equal(normalizeSearchImportQuery(undefined), "");
  });
});

describe("validateSearchImportQuery — accepts real product searches", () => {
  for (const q of [
    "mouse",
    "jbl speaker",
    "redmi note 12 display",
    "s21 main board flex",
    "nova 3i motherboard",
    "Original Xiaomi 120W USB Type C Cable 6A",
    "ssd drive hdd 2.5 hard disk ssd 120gb",
    "USB-C hub to 4K HDMI-compatible",
    "রেডমি নোট ১২ ডিসপ্লে",
    "a10",
    // 160-char pasted title from searchImportLog
    "Original Xiaomi 120W USB Type C Cable Tipo 6A 67W Turbo Fast Charging For Mi 17 Pro Max 15 14 Ultra 13 Pro Redmi Note 15 Poco X6",
    "Samsung 747137-001 board",
  ]) {
    test(JSON.stringify(q), () => {
      const result = validateSearchImportQuery(q);
      assert.equal(result.ok, true, `rejected with ${result.reason}`);
    });
  }

  test("returns the normalized query", () => {
    assert.deepEqual(validateSearchImportQuery("  jbl   speaker "), { ok: true, query: "jbl speaker" });
  });
});

describe("validateSearchImportQuery — rejects the junk seen in searchImportLog", () => {
  const cases = [
    ["", "TOO_SHORT"],
    ["ht", "TOO_SHORT"],
    ["  m ", "TOO_SHORT"],
    ["1005", "DIGITS_ONLY"],
    ["10050093534457", "DIGITS_ONLY"],
    ["1005009353445701", "DIGITS_ONLY"],
    ["100 500", "DIGITS_ONLY"],
    ["https://www.aliexpress.com/item/1005012402680375.html?spm=a2g0o", "URL"],
    ["www.aliexpress.com", "URL"],
    ["aliexpress.com item", "URL"],
    ["item/32595324956.html", "URL"],
    ["htm", "CODE_LIKE"],
    ["html", "CODE_LIKE"],
    ["html a", "CODE_LIKE"],
    ["html and usb hub", "CODE_LIKE"],
    ["html_and_usb_hub_f", "CODE_LIKE"],
    ["<div>phone</div>", "CODE_LIKE"],
    ["a=1; drop", "CODE_LIKE"],
    ["--- ...", "DIGITS_ONLY"],
    ["!!!???", "NO_LETTERS"],
    ["aliexpress/item/1005009353445701", "URL"],
    ["aliexpress item 1005009353445701", "URL"],
    ["x".repeat(201), "TOO_LONG"],
  ];
  for (const [q, reason] of cases) {
    test(`${JSON.stringify(q.slice(0, 40))} -> ${reason}`, () => {
      const result = validateSearchImportQuery(q);
      assert.equal(result.ok, false);
      assert.equal(result.reason, reason);
    });
  }
});
