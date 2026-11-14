// -----------------------------------------------------------------------------
// Variant label fields carried through import.
//
//   sourceAttributeName — AliExpress's own attribute name for the variant's
//     first property (e.g. "Color", "SSD Capacity"), stored as-is for
//     reference. NOT shown to shoppers directly: sellers routinely misuse
//     "Color" for models/storage/frames (70 of 71 products, 2026-11-14), so
//     the storefront label is derived from the values instead (see
//     catalog/variantLabel.js and lib/utils/variant_selector_model.dart).
//   attributeName — a manually set per-variant name; never produced from
//     AliExpress data, only carried through if a caller sends it.
// -----------------------------------------------------------------------------

const { resolveAliExpressVariantAttributeName } = require("./variantName");

function textValue(value) {
  return String(value ?? "").trim();
}

/** Label fields for one raw AliExpress SKU (normalizeAliExpressProduct). */
function sourceLabelFieldsFromSku(sku) {
  const sourceAttributeName = resolveAliExpressVariantAttributeName(sku);
  return sourceAttributeName ? { sourceAttributeName } : {};
}

/** Label fields to keep from an incoming variant (importVariants). */
function carryVariantLabelFields(item) {
  const v = item && typeof item === "object" ? item : {};
  const out = {};
  const source = textValue(v.sourceAttributeName);
  const manual = textValue(v.attributeName);
  if (source) out.sourceAttributeName = source;
  if (manual) out.attributeName = manual;
  return out;
}

module.exports = { sourceLabelFieldsFromSku, carryVariantLabelFields };
