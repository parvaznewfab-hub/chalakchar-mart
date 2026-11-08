const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { resolveVerificationChallenge } = require("../meta/webhookChallenge");

describe("resolveVerificationChallenge", () => {
  test("returns the challenge when mode and verify token both match", () => {
    const result = resolveVerificationChallenge({
      mode: "subscribe",
      verifyToken: "secret_token",
      challenge: "12345",
      expectedVerifyToken: "secret_token",
    });
    assert.equal(result, "12345");
  });

  test("returns the challenge as a string even if numeric", () => {
    const result = resolveVerificationChallenge({
      mode: "subscribe",
      verifyToken: "t",
      challenge: 12345,
      expectedVerifyToken: "t",
    });
    assert.equal(result, "12345");
    assert.equal(typeof result, "string");
  });

  test("rejects a mismatched verify token", () => {
    const result = resolveVerificationChallenge({
      mode: "subscribe",
      verifyToken: "wrong",
      challenge: "12345",
      expectedVerifyToken: "secret_token",
    });
    assert.equal(result, null);
  });

  test("rejects a mode other than subscribe", () => {
    const result = resolveVerificationChallenge({
      mode: "unsubscribe",
      verifyToken: "secret_token",
      challenge: "12345",
      expectedVerifyToken: "secret_token",
    });
    assert.equal(result, null);
  });

  test("rejects when no verify token is configured server-side", () => {
    const result = resolveVerificationChallenge({
      mode: "subscribe",
      verifyToken: "secret_token",
      challenge: "12345",
      expectedVerifyToken: "",
    });
    assert.equal(result, null);
  });

  test("rejects a missing verifyToken from the request", () => {
    const result = resolveVerificationChallenge({
      mode: "subscribe",
      verifyToken: "",
      challenge: "12345",
      expectedVerifyToken: "secret_token",
    });
    assert.equal(result, null);
  });

  test("rejects a missing challenge even when mode/token match", () => {
    const result = resolveVerificationChallenge({
      mode: "subscribe",
      verifyToken: "secret_token",
      challenge: undefined,
      expectedVerifyToken: "secret_token",
    });
    assert.equal(result, null);
  });
});
