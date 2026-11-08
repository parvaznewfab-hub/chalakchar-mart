const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("crypto");

const { verifyMetaSignature, WebhookVerificationError } = require("../meta/signatureVerify");

const APP_SECRET = "test_app_secret";

function sign(body, secret = APP_SECRET) {
  return `sha256=${crypto.createHmac("sha256", secret).update(body).digest("hex")}`;
}

describe("verifyMetaSignature", () => {
  test("accepts a correctly signed body", () => {
    const rawBody = JSON.stringify({ hello: "world" });
    assert.equal(
      verifyMetaSignature({ rawBody, signatureHeader: sign(rawBody), appSecret: APP_SECRET }),
      true
    );
  });

  test("works against a Buffer raw body, not just a string", () => {
    const rawBody = Buffer.from(JSON.stringify({ a: 1 }));
    assert.equal(
      verifyMetaSignature({ rawBody, signatureHeader: sign(rawBody.toString("utf8")), appSecret: APP_SECRET }),
      true
    );
  });

  test("rejects a signature computed with the wrong secret", () => {
    const rawBody = JSON.stringify({ hello: "world" });
    assert.throws(
      () => verifyMetaSignature({ rawBody, signatureHeader: sign(rawBody, "wrong_secret"), appSecret: APP_SECRET }),
      WebhookVerificationError
    );
  });

  test("rejects a tampered body (signature no longer matches)", () => {
    const rawBody = JSON.stringify({ hello: "world" });
    const signature = sign(rawBody);
    assert.throws(
      () => verifyMetaSignature({ rawBody: JSON.stringify({ hello: "tampered" }), signatureHeader: signature, appSecret: APP_SECRET }),
      WebhookVerificationError
    );
  });

  test("rejects a missing signature header", () => {
    assert.throws(
      () => verifyMetaSignature({ rawBody: "{}", signatureHeader: undefined, appSecret: APP_SECRET }),
      (err) => err instanceof WebhookVerificationError && err.code === "MISSING_SIGNATURE"
    );
  });

  test("rejects a missing app secret", () => {
    assert.throws(
      () => verifyMetaSignature({ rawBody: "{}", signatureHeader: "sha256=abc", appSecret: "" }),
      (err) => err instanceof WebhookVerificationError && err.code === "MISSING_SECRET"
    );
  });

  test("rejects an empty raw body", () => {
    assert.throws(
      () => verifyMetaSignature({ rawBody: "", signatureHeader: "sha256=abc", appSecret: APP_SECRET }),
      (err) => err instanceof WebhookVerificationError && err.code === "MISSING_RAW_BODY"
    );
  });

  test("rejects a signature header missing the sha256= prefix", () => {
    const rawBody = "{}";
    const bareHex = crypto.createHmac("sha256", APP_SECRET).update(rawBody).digest("hex");
    assert.throws(
      () => verifyMetaSignature({ rawBody, signatureHeader: bareHex, appSecret: APP_SECRET }),
      (err) => err instanceof WebhookVerificationError && err.code === "MALFORMED_SIGNATURE"
    );
  });

  test("a signature of different length than expected is rejected, not thrown as a crypto error", () => {
    const rawBody = "{}";
    assert.throws(
      () => verifyMetaSignature({ rawBody, signatureHeader: "sha256=short", appSecret: APP_SECRET }),
      (err) => err instanceof WebhookVerificationError && err.code === "INVALID_SIGNATURE"
    );
  });
});
