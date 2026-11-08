const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { shouldTriggerSearchImportFallback } = require("../messaging/searchImportGuard");

describe("shouldTriggerSearchImportFallback", () => {
  test("a genuine product-search miss (even a single word) should trigger", () => {
    assert.equal(shouldTriggerSearchImportFallback("iphone"), true);
    assert.equal(shouldTriggerSearchImportFallback("gaming mouse"), true);
    assert.equal(shouldTriggerSearchImportFallback("napa extra"), true);
  });

  test("common greetings/chit-chat should not trigger", () => {
    for (const text of ["hi", "Hi", "hello", "hey", "ok", "Okay", "thanks", "thank you", "bye", "ha", "na"]) {
      assert.equal(shouldTriggerSearchImportFallback(text), false, `expected "${text}" not to trigger`);
    }
  });

  test("Bangla chit-chat should not trigger", () => {
    for (const text of ["হাই", "হ্যালো", "ধন্যবাদ", "ঠিক আছে"]) {
      assert.equal(shouldTriggerSearchImportFallback(text), false, `expected "${text}" not to trigger`);
    }
  });

  test("trailing punctuation/emoji on a chit-chat phrase still counts as chit-chat", () => {
    assert.equal(shouldTriggerSearchImportFallback("thanks!"), false);
    assert.equal(shouldTriggerSearchImportFallback("ok😊"), false);
    assert.equal(shouldTriggerSearchImportFallback("Hi!!"), false);
  });

  test("blank text or a bare 1-char scrap does not trigger", () => {
    assert.equal(shouldTriggerSearchImportFallback(""), false);
    assert.equal(shouldTriggerSearchImportFallback("   "), false);
    assert.equal(shouldTriggerSearchImportFallback("k"), false);
    assert.equal(shouldTriggerSearchImportFallback("."), false);
  });
});
