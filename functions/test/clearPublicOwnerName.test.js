const test = require("node:test");
const assert = require("node:assert/strict");
const { planClearOwnerName } = require("../scripts/clearPublicOwnerName");

test("private has ownerName: delete the public one", () => {
  assert.equal(planClearOwnerName({ ownerName: "Old" }, { ownerName: "New" }).action, "delete");
  assert.equal(planClearOwnerName({ ownerName: "Same" }, { ownerName: "Same" }).action, "delete");
});

test("private ownerName missing or blank: refuse (public is the only copy)", () => {
  assert.equal(planClearOwnerName({ ownerName: "Old" }, {}).action, "refuse");
  assert.equal(planClearOwnerName({ ownerName: "Old" }, { ownerName: "  " }).action, "refuse");
  assert.equal(planClearOwnerName({ ownerName: "Old" }, { ownerName: null }).action, "refuse");
  assert.equal(planClearOwnerName({ ownerName: "Old" }, undefined).action, "refuse");
});

test("no public ownerName: nothing to do; no public doc: refuse", () => {
  assert.equal(planClearOwnerName({ shopName: "S" }, { ownerName: "New" }).action, "nothing");
  assert.equal(planClearOwnerName(null, { ownerName: "New" }).action, "refuse");
});
