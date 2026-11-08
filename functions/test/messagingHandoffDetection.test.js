const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  containsHandoffKeyword,
  hasRepeatedUnresolvedQuestion,
  isLowConfidenceReply,
} = require("../messaging/handoffDetection");

describe("containsHandoffKeyword", () => {
  test("matches English keywords case-insensitively", () => {
    assert.equal(containsHandoffKeyword("I want to talk to a MANAGER please"), true);
  });

  test("matches Bangla script keywords", () => {
    assert.equal(containsHandoffKeyword("আমি একজন এজেন্ট এর সাথে কথা বলতে চাই"), true);
  });

  test("matches romanized Bangla phrase", () => {
    assert.equal(containsHandoffKeyword("ami kotha bolte chai apnader shathe"), true);
  });

  test("ordinary product questions do not trigger it", () => {
    assert.equal(containsHandoffKeyword("Napa Extra er price koto?"), false);
  });

  test("blank text does not trigger it", () => {
    assert.equal(containsHandoffKeyword(""), false);
  });
});

describe("hasRepeatedUnresolvedQuestion", () => {
  test("false when asked for the first time", () => {
    assert.equal(hasRepeatedUnresolvedQuestion([], "delivery ki available?"), false);
  });

  test("false on the second ask (threshold not yet reached)", () => {
    const history = [{ sender: "customer", text: "delivery ki available?" }];
    assert.equal(hasRepeatedUnresolvedQuestion(history, "delivery ki available?"), false);
  });

  test("true on the third ask, matching the default threshold", () => {
    const history = [
      { sender: "customer", text: "delivery ki available?" },
      { sender: "bot", text: "ভালো প্রশ্ন..." },
      { sender: "customer", text: "delivery ki available?" },
    ];
    assert.equal(hasRepeatedUnresolvedQuestion(history, "delivery ki available?"), true);
  });

  test("punctuation/whitespace differences still count as the same question", () => {
    const history = [
      { sender: "customer", text: "delivery ki available??" },
      { sender: "customer", text: "delivery  ki available" },
    ];
    assert.equal(hasRepeatedUnresolvedQuestion(history, "delivery ki available."), true);
  });

  test("bot messages are never counted, only customer messages", () => {
    const history = [
      { sender: "bot", text: "delivery ki available?" },
      { sender: "bot", text: "delivery ki available?" },
    ];
    assert.equal(hasRepeatedUnresolvedQuestion(history, "delivery ki available?"), false);
  });

  test("a different question resets the count", () => {
    const history = [
      { sender: "customer", text: "delivery ki available?" },
      { sender: "customer", text: "delivery ki available?" },
    ];
    assert.equal(hasRepeatedUnresolvedQuestion(history, "price koto?"), false);
  });

  test("custom threshold is respected", () => {
    const history = [{ sender: "customer", text: "hi" }];
    assert.equal(hasRepeatedUnresolvedQuestion(history, "hi", 2), true);
  });
});

describe("isLowConfidenceReply", () => {
  test("empty/blank reply is low-confidence", () => {
    assert.equal(isLowConfidenceReply(""), true);
    assert.equal(isLowConfidenceReply("   "), true);
  });

  test("a normal helpful reply is not low-confidence", () => {
    assert.equal(isLowConfidenceReply("আমরা প্রতিদিন সকাল ৯টা থেকে রাত ১০টা পর্যন্ত ডেলিভারি করি।"), false);
  });

  test("an English uncertainty phrase is detected", () => {
    assert.equal(isLowConfidenceReply("I'm not sure about that, sorry."), true);
  });

  test("a Bangla uncertainty phrase is detected", () => {
    assert.equal(isLowConfidenceReply("দুঃখিত, আমি নিশ্চিত না এই বিষয়ে।"), true);
  });
});
