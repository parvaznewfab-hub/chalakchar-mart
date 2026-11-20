const test = require("node:test");
const assert = require("node:assert/strict");
const { planRestore, sourcesFromBackup } = require("../scripts/restorePrivateProfiles");
const { planProfileMove } = require("../scripts/movePrivateProfiles");

test("restore puts back every private value missing from the public doc", () => {
  const plan = planRestore("vendor", { shopName: "S" }, { phone: "017", payoutAccount: "bkash", commissionPercent: 0 });
  assert.deepEqual(plan, { set: { phone: "017", payoutAccount: "bkash", commissionPercent: 0 }, conflicts: [] });
});

test("same value already in the public doc: nothing to do for that key", () => {
  assert.deepEqual(planRestore("vendor", { phone: "017" }, { phone: "017" }), { set: {}, conflicts: [] });
});

test("DIFFERENT value in the public doc: conflict, nothing planned", () => {
  const plan = planRestore("vendor", { phone: "019" }, { phone: "017", email: "a@b" });
  assert.deepEqual(plan, { set: {}, conflicts: ["phone"] });
});

test("only private keys are restored (no status, no shopName from a bad source)", () => {
  const plan = planRestore("vendor", {}, { status: "approved", shopName: "x", phone: "017", updatedAt: "t" });
  assert.deepEqual(plan.set, { phone: "017" });
});

test("rider: NID back, money / phone never touched", () => {
  const plan = planRestore("rider", { phone: "018", codDue: 5 }, { nidNumber: "1", address: "A", codDue: 0 });
  assert.deepEqual(plan.set, { nidNumber: "1", address: "A" });
});

test("move then restore from its backup gives the original public doc back", () => {
  const original = {
    shopName: "S", phone: "017", email: "", nidFront: "https://x/v0/b/b/o/vendors%2Fv1%2Fd%2Fn.jpeg?token=t",
    payoutAccount: "bkash", withdrawableBalance: 0,
  };
  const move = planProfileMove("vendor", original, {});
  const backupEntry = { collection: "vendors", id: "v1", removed: Object.fromEntries(move.remove.map((k) => [k, original[k]])) };
  const afterMove = Object.fromEntries(Object.entries(original).filter(([k]) => !move.remove.includes(k)));
  const [src] = sourcesFromBackup([backupEntry]);
  const restore = planRestore(src.kind, afterMove, src.values);
  const restored = { ...afterMove, ...restore.set };
  // Empty leftovers ("") are not written back; everything with a value is.
  assert.deepEqual(restored, { shopName: "S", phone: "017", nidFront: original.nidFront, payoutAccount: "bkash", withdrawableBalance: 0 });
});

test("sourcesFromBackup rejects a malformed file", () => {
  assert.throws(() => sourcesFromBackup({}), /JSON array/);
  assert.throws(() => sourcesFromBackup([{ collection: "users", id: "x", removed: {} }]), /collection/);
  assert.deepEqual(sourcesFromBackup([{ collection: "deliveryPartners", id: "r1", removed: { nidNumber: "1" } }]),
    [{ kind: "rider", id: "r1", values: { nidNumber: "1" } }]);
});
