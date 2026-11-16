const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");
const { modelFieldsForName } = require("../catalog/deviceModel");

// Same fixture as test/device_model_test.dart (Dart mirror).
const { cases } = require(path.join(__dirname, "..", "..", "test", "fixtures", "device_model_cases.json"));

for (const c of cases) {
  test(`fixture: ${c.name.slice(0, 70)}`, () => {
    assert.deepEqual(modelFieldsForName(c.name), { modelKeys: c.modelKeys, modelSeries: c.modelSeries });
  });
}

const keys = (name) => modelFieldsForName(name).modelKeys;

test("Pro / Pro Max / mini are separate models of one series", () => {
  assert.deepEqual(keys("Motherboard For iPhone 12 64g"), ["iphone 12"]);
  assert.deepEqual(keys("Motherboard For iPhone 12 Pro 128g"), ["iphone 12 pro"]);
  assert.deepEqual(keys("Motherboard For iPhone 12 Pro Max 128g"), ["iphone 12 pro max"]);
  assert.deepEqual(keys("Motherboard For iPhone 12 Mini"), ["iphone 12 mini"]);
  assert.deepEqual(modelFieldsForName("For iPhone 12 Pro Max").modelSeries, ["iphone 12"]);
});

test("Lite / e / s / FE / Ultra / + stay on the model", () => {
  assert.deepEqual(keys("LCD for HUAWEI P30 Lite"), ["huawei p30 lite"]);
  assert.deepEqual(keys("LCD For Huawei Nova 4e"), ["huawei nova 4e"]);
  assert.deepEqual(keys("For Samsung Galaxy A52s 5G"), ["samsung a52s"]);
  assert.deepEqual(keys("for Samsung S20FE 5G"), ["samsung s20 fe"]);
  assert.deepEqual(keys("For Samsung S21Ultra"), ["samsung s21 ultra"]);
  assert.deepEqual(keys("for SAMSUNG S21+ 5G"), ["samsung s21 plus"]);
  assert.deepEqual(keys("for SAMSUNG S21 Plus"), ["samsung s21 plus"]);
});

test("lists name every model", () => {
  assert.deepEqual(keys("For iPhone X XR XS Max"), ["iphone x", "iphone xr", "iphone xs", "iphone xs max"]);
  assert.deepEqual(keys("For iPhone XS Max Cleaned iCloud"), ["iphone xs max"]);
});

test("no device model in non-phone names", () => {
  assert.deepEqual(keys("Netac NVMe SSD M2 1TB 2TB 500GB PCIe3.0 M.2 2280"), []);
  assert.deepEqual(keys("High Speed SSD 500GB Laptop Desktop PC Pro Max Storage"), []);
  assert.deepEqual(keys(""), []);
  assert.deepEqual(keys(null), []);
});

const { modelKeysUpdate, isModelKeysWrite } = require("../catalog/deviceModel");

test("modelKeysUpdate: writes once, then nothing (no trigger loop)", () => {
  const product = { name: "Motherboard For iPhone 12 Pro Max" };
  const update = modelKeysUpdate(product, "STAMP");
  assert.deepEqual(update, {
    modelKeys: ["iphone 12 pro max"], modelSeries: ["iphone 12"],
    modelKeysAt: "STAMP", lastWriteSource: "model_keys",
  });
  assert.equal(modelKeysUpdate({ ...product, ...update }, "STAMP2"), null);
  // A product with no device model still gets empty lists once.
  assert.deepEqual(modelKeysUpdate({ name: "Netac SSD 1TB" }, "S").modelKeys, []);
  assert.equal(modelKeysUpdate({ name: "Netac SSD 1TB", modelKeys: [], modelSeries: [] }, "S"), null);
});

test("isModelKeysWrite: only the write that sets a new stamp", () => {
  const t = (ms) => ({ toMillis: () => ms });
  assert.equal(isModelKeysWrite({}, { modelKeysAt: t(5) }), true);
  assert.equal(isModelKeysWrite({ modelKeysAt: t(5) }, { modelKeysAt: t(5) }), false);
  assert.equal(isModelKeysWrite({}, {}), false);
});
