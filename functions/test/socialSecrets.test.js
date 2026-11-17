const test = require("node:test");
const assert = require("node:assert/strict");
const {
  SECRET_SOCIAL_API_KEYS,
  mergeSocialApiSecrets,
  secretsInPublicSocialApi,
} = require("../settings/socialSecrets");
const { planSecretsMove } = require("../scripts/moveSocialSecrets");

test("secret keys are exactly the token fields", () => {
  assert.deepEqual([...SECRET_SOCIAL_API_KEYS].sort(), [
    "facebookPageAccessToken",
    "instagramAccessToken",
    "messengerPageAccessToken",
    "tiktokClientSecret",
    "whatsappAccessToken",
  ]);
});

test("merge: app_secrets value wins over the old public one", () => {
  const merged = mergeSocialApiSecrets(
    { facebookPageId: "p1", facebookPageAccessToken: "old" },
    { facebookPageAccessToken: "new" }
  );
  assert.equal(merged.facebookPageAccessToken, "new");
  assert.equal(merged.facebookPageId, "p1");
});

test("merge: before the move, public tokens still work", () => {
  const merged = mergeSocialApiSecrets({ whatsappAccessToken: "w" }, {});
  assert.equal(merged.whatsappAccessToken, "w");
});

test("merge: empty secret does not wipe a public value; after the move public is empty", () => {
  assert.equal(mergeSocialApiSecrets({ whatsappAccessToken: "w" }, { whatsappAccessToken: " " }).whatsappAccessToken, "w");
  assert.equal(mergeSocialApiSecrets({ whatsappAccessToken: "" }, { whatsappAccessToken: "s" }).whatsappAccessToken, "s");
});

test("merge: non-secret keys in app_secrets are ignored", () => {
  const merged = mergeSocialApiSecrets({ facebookPageId: "p1" }, { facebookPageId: "evil", other: "x" });
  assert.equal(merged.facebookPageId, "p1");
  assert.equal(merged.other, undefined);
});

test("merge: tolerates missing docs", () => {
  assert.deepEqual(mergeSocialApiSecrets(undefined, null), {});
});

test("secretsInPublicSocialApi lists present keys and copies only non-empty ones", () => {
  const r = secretsInPublicSocialApi({ facebookPageId: "p", facebookPageAccessToken: "t", whatsappAccessToken: "" });
  assert.deepEqual(r.present.sort(), ["facebookPageAccessToken", "whatsappAccessToken"]);
  assert.deepEqual(r.toCopy, { facebookPageAccessToken: "t" });
});

test("plan: copies tokens, removes them from public, keeps public ids", () => {
  const plan = planSecretsMove(
    { socialApi: { facebookPageId: "p", facebookPageAccessToken: "t", tiktokClientSecret: "s" } },
    {}
  );
  assert.deepEqual(plan.copyKeys.sort(), ["facebookPageAccessToken", "tiktokClientSecret"]);
  assert.deepEqual(plan.removeKeys.sort(), ["facebookPageAccessToken", "tiktokClientSecret"]);
  assert.deepEqual(plan.conflicts, []);
});

test("plan: a different value already in app_secrets is a conflict, never overwritten", () => {
  const plan = planSecretsMove(
    { socialApi: { whatsappAccessToken: "old" } },
    { socialApi: { whatsappAccessToken: "newer" } }
  );
  assert.deepEqual(plan.copyKeys, []);
  assert.deepEqual(plan.conflicts, ["whatsappAccessToken"]);
  assert.deepEqual(plan.removeKeys, []);
});

test("plan: same value already copied -> only remove from public", () => {
  const plan = planSecretsMove(
    { socialApi: { whatsappAccessToken: "same" } },
    { socialApi: { whatsappAccessToken: "same" } }
  );
  assert.deepEqual(plan.copyKeys, []);
  assert.deepEqual(plan.removeKeys, ["whatsappAccessToken"]);
});

test("plan: nothing to do when public has no secrets", () => {
  const plan = planSecretsMove({ socialApi: { facebookPageId: "p" } }, {});
  assert.deepEqual(plan, { copyKeys: [], removeKeys: [], conflicts: [] });
});
