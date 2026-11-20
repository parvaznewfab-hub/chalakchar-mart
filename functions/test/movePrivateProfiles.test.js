const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  VENDOR_PRIVATE_KEYS,
  RIDER_PRIVATE_KEYS,
  planProfileMove,
  storagePathFromLink,
} = require("../scripts/movePrivateProfiles");

const REPO = path.resolve(__dirname, "..", "..");
const LINK = "https://firebasestorage.googleapis.com/v0/b/chalakchar-mart.firebasestorage.app/o/"
  + "vendors%2Fv1%2Fdocuments%2Fnid-front-1.jpeg?alt=media&token=SECRET-TOKEN";

// ---- the three key lists must agree: script, Dart app, firestore.rules ----

function dartList(name) {
  const src = fs.readFileSync(path.join(REPO, "lib/utils/private_profile_fields.dart"), "utf8");
  const m = src.match(new RegExp(`const List<String> ${name} = \\[([\\s\\S]*?)\\];`));
  assert.ok(m, `${name} not found in private_profile_fields.dart`);
  return [...m[1].replace(/\/\/.*$/gm, "").matchAll(/'([^']+)'/g)].map((x) => x[1]);
}

function rulesFunctionList(name) {
  const src = fs.readFileSync(path.join(REPO, "firestore.rules"), "utf8");
  const m = src.match(new RegExp(`function ${name}\\(\\) \\{[\\s\\S]*?return \\[([\\s\\S]*?)\\];`));
  assert.ok(m, `${name} not found in firestore.rules`);
  return [...m[1].replace(/\/\/.*$/gm, "").matchAll(/'([^']+)'/g)].map((x) => x[1]);
}

test("vendor keys: script == Dart (profile + money) == rules", () => {
  const dart = [...dartList("kVendorPrivateProfileKeys"), ...dartList("kVendorPrivateMoneyKeys")];
  const rules = [...rulesFunctionList("vendorPrivateProfileKeys"), ...rulesFunctionList("vendorPrivateMoneyKeys")];
  assert.deepEqual([...VENDOR_PRIVATE_KEYS].sort(), [...dart].sort());
  assert.deepEqual([...VENDOR_PRIVATE_KEYS].sort(), [...rules].sort());
});

test("rider keys: script == Dart == rules (NID keys + address/email/note)", () => {
  const rules = [...rulesFunctionList("riderPrivateNidKeys"), "address", "email", "note"];
  assert.deepEqual([...RIDER_PRIVATE_KEYS].sort(), [...dartList("kRiderPrivateKeys")].sort());
  assert.deepEqual([...RIDER_PRIVATE_KEYS].sort(), [...rules].sort());
});

test("every private key is in the public-doc guard of firestore.rules (step 6: no private key at all)", () => {
  const src = fs.readFileSync(path.join(REPO, "firestore.rules"), "utf8");
  const body = (name) => src.match(new RegExp(`function ${name}\\(\\) \\{([\\s\\S]*?)\\n    \\}`))[1];
  const listed = (text) => new Set([...text.matchAll(/'([A-Za-z]+)'/g)].map((m) => m[1]));
  // The guards themselves: one keys().hasAny() over the full lists.
  assert.match(body("noVendorPrivateKeys"), /keys\(\)\.hasAny\(vendorAllPrivateKeys\(\)\)/);
  assert.match(body("noRiderPrivateKeys"), /keys\(\)\.hasAny\(riderAllPrivateKeys\(\)\)/);
  assert.match(body("vendorAllPrivateKeys"), /vendorPrivateProfileKeys\(\)\.concat\(vendorPrivateMoneyKeys\(\)\)/);
  const vendorKeys = listed(body("vendorPrivateProfileKeys") + body("vendorPrivateMoneyKeys"));
  assert.deepEqual([...vendorKeys].sort(), [...VENDOR_PRIVATE_KEYS].sort());
  const riderKeys = listed(body("riderPrivateNidKeys") + body("riderAllPrivateKeys"));
  assert.deepEqual([...riderKeys].sort(), [...RIDER_PRIVATE_KEYS].sort());
});

// ---- the plan ----

test("vendor like the live one: contact + payout copied, links become paths, nothing else", () => {
  const pub = {
    shopName: "Shop", status: "approved", ownerId: "v1",
    phone: "01700000000", email: "a@b.c", address: "Road 1", ownerName: "Owner", note: "",
    payoutAccount: "bkash 017", nidFront: LINK, nidBack: LINK.replace("nid-front-1", "nid-back-1"),
    tradeLicense: LINK.replace("nid-front-1", "trade-license-1"),
  };
  const plan = planProfileMove("vendor", pub, {});
  assert.deepEqual(plan.conflicts, []);
  assert.deepEqual(plan.copy, {
    phone: "01700000000", email: "a@b.c", address: "Road 1", ownerName: "Owner", payoutAccount: "bkash 017",
    nidFrontPath: "vendors/v1/documents/nid-front-1.jpeg",
    nidBackPath: "vendors/v1/documents/nid-back-1.jpeg",
    tradeLicensePath: "vendors/v1/documents/trade-license-1.jpeg",
  });
  assert.deepEqual([...plan.remove].sort(),
    ["address", "email", "nidBack", "nidFront", "note", "ownerName", "payoutAccount", "phone", "tradeLicense"]);
  assert.ok(!JSON.stringify(plan.copy).includes("SECRET-TOKEN"), "a token must never be copied");
  assert.ok(!("shopName" in plan.copy) && !plan.remove.includes("shopName"));
});

test("rider like the live one: NID/address/email moved; links dropped, existing paths kept", () => {
  const pub = {
    name: "R", phone: "018", status: "approved", totalEarning: 100, codDue: 5,
    nidNumber: "1234567890", address: "House", email: "r@x.y", note: "",
    nidFrontUrl: LINK, nidFrontPath: "delivery_partner_documents/u/nid_front_u.jpg",
    nidBackUrl: LINK, nidBackPath: "delivery_partner_documents/u/nid_back_u.jpg",
  };
  const plan = planProfileMove("rider", pub, {});
  assert.deepEqual(plan.copy, {
    nidNumber: "1234567890", address: "House", email: "r@x.y",
    nidFrontPath: "delivery_partner_documents/u/nid_front_u.jpg",
    nidBackPath: "delivery_partner_documents/u/nid_back_u.jpg",
  });
  assert.ok(plan.remove.includes("nidFrontUrl") && plan.remove.includes("nidBackUrl"));
  // Money and the phone (copied to orders for customers) stay public.
  for (const k of ["phone", "totalEarning", "codDue", "name"]) assert.ok(!plan.remove.includes(k), k);
});

test("same value already in the private doc: not copied again, still removed from public", () => {
  const plan = planProfileMove("vendor", { phone: "017" }, { phone: "017" });
  assert.deepEqual(plan.copy, {});
  assert.deepEqual(plan.remove, ["phone"]);
});

test("DIFFERENT value in the private doc: conflict, nothing planned at all", () => {
  const plan = planProfileMove("vendor", { phone: "017", email: "a@b" }, { phone: "019" });
  assert.deepEqual(plan.conflicts, ["phone"]);
  assert.deepEqual(plan.copy, {});
  assert.deepEqual(plan.remove, []);
});

test("conflict also for a link whose path differs from the private path", () => {
  const plan = planProfileMove("vendor", { nidFront: LINK }, { nidFrontPath: "vendors/v1/documents/other.jpeg" });
  assert.deepEqual(plan.conflicts, ["nidFrontPath"]);
});

test("0 balances and 0% commission are real values and move", () => {
  const plan = planProfileMove("vendor", { commissionPercent: 0, withdrawableBalance: 0 }, {});
  assert.deepEqual(plan.copy, { commissionPercent: 0, withdrawableBalance: 0 });
});

test("empty leftovers are only removed; a non-Storage link is dropped, not copied", () => {
  const plan = planProfileMove("vendor", { note: "", phone: "  ", nidBack: "https://example.com/x.jpg" }, {});
  assert.deepEqual(plan.copy, {});
  assert.deepEqual([...plan.remove].sort(), ["nidBack", "note", "phone"]);
  assert.deepEqual(plan.skippedLinks, ["nidBack"]);
});

test("nothing private in the public doc: nothing to do", () => {
  const plan = planProfileMove("vendor", { shopName: "S", status: "approved" }, {});
  assert.deepEqual(plan, { copy: {}, remove: [], conflicts: [], skippedLinks: [] });
});

test("storagePathFromLink: path only, never the token", () => {
  assert.equal(storagePathFromLink(LINK), "vendors/v1/documents/nid-front-1.jpeg");
  assert.equal(storagePathFromLink("vendors/v1/documents/x.jpeg"), "vendors/v1/documents/x.jpeg");
  assert.equal(storagePathFromLink(""), "");
  assert.equal(storagePathFromLink("https://example.com/a.jpg"), "");
});

test("the script writes its backup outside the repo, never prints values", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "scripts", "movePrivateProfiles.js"), "utf8");
  assert.match(src, /path\.join\(os\.homedir\(\), "cc-backups"\)/);
  // console output only uses lengths()/key names, never raw values
  const logs = src.split("\n").filter((l) => l.includes("console.log"));
  for (const line of logs) assert.doesNotMatch(line, /publicData\[|\.copy\[|pub\[/, line.trim());
});
