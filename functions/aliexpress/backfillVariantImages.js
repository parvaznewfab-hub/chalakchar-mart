const { matchAliExpressVariant, cleanVariantNameForMatch, withSourceSkuIds } = require("./variantMatch");

// -----------------------------------------------------------------------------
// Pure computation for the AliExpress variant-image backfill. Split into two
// steps so a concurrent admin edit can never be silently overwritten:
//
// 1. computeVariantImagePatches(existingVariants, freshVariants) — decides,
//    against the variants read at the START of the run, WHICH variants
//    should get a new image and what identity field/value confidently
//    matched them. Produces "patches", not a final array.
//
// 2. applyVariantImagePatchesToLatest(latestVariants, patches) — re-applies
//    those patches onto a FRESH re-read of the product's variants (taken
//    right before writing), re-locating each patch's target by the SAME
//    identity field/value rather than by array position. If a patch's
//    target can no longer be found confidently in the latest data, it is
//    skipped and reported — never overwritten blindly. Every other field on
//    every variant (including matched ones) comes from the latest read, so
//    a concurrent admin price/stock edit is preserved automatically.
// -----------------------------------------------------------------------------

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function mapValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

/**
 * @param {object[]} existingVariants product.variants as read at the start of the run
 * @param {object[]} freshVariants freshly-fetched AliExpress variants
 * @returns {{ patches: object[], skipped: object[] }}
 */
function computeVariantImagePatches(existingVariants, freshVariants) {
  const existing = Array.isArray(existingVariants) ? existingVariants : [];
  // Saved variants match by sourceSkuId, fresh ones only carry skuId — see
  // withSourceSkuIds. Without this, no saved variant ever matched.
  const fresh = withSourceSkuIds(freshVariants);
  const patches = [];
  const skipped = [];

  existing.forEach((rawVariant, index) => {
    const variant = mapValue(rawVariant);
    const name = textValue(variant.name || variant.unit || variant.variantName, `Variant ${index + 1}`);
    const { matched, matchField, ambiguous } = matchAliExpressVariant(variant, fresh);

    if (ambiguous) {
      skipped.push({ index, name, reason: `ambiguous_match_by_${matchField}` });
      return;
    }
    if (!matched) {
      skipped.push({ index, name, reason: "no_confident_match" });
      return;
    }
    // An identifier match is only trusted when the names agree too: some
    // imports saved another variant's SKU on a variant (see
    // pickFreshVariantForSaved), which would put the wrong image on it.
    if (matchField !== "name") {
      const savedName = cleanVariantNameForMatch(name).replace(/\s+/g, " ");
      const freshName = cleanVariantNameForMatch(matched.name).replace(/\s+/g, " ");
      if (savedName && freshName && savedName !== freshName) {
        skipped.push({ index, name, reason: "sku_name_mismatch" });
        return;
      }
    }

    const image = textValue(matched.image || matched.imageUrl);
    if (!image) {
      skipped.push({ index, name, reason: "fresh_variant_has_no_image" });
      return;
    }

    const matchValue = matchField === "name"
      ? cleanVariantNameForMatch(name)
      : textValue(variant[matchField]);

    patches.push({
      index,
      name,
      matchField,
      matchValue,
      image,
      imageUrl: textValue(matched.imageUrl) || image,
    });
  });

  return { patches, skipped };
}

/**
 * @param {object[]} latestVariants product.variants re-read immediately before writing
 * @param {object[]} patches output of computeVariantImagePatches().patches
 * @returns {{ updatedVariants: object[], appliedCount: number, reappliedSkipped: object[] }}
 */
function applyVariantImagePatchesToLatest(latestVariants, patches) {
  const updatedVariants = (Array.isArray(latestVariants) ? latestVariants : [])
    .map((variant) => ({ ...mapValue(variant) }));
  const reappliedSkipped = [];
  let appliedCount = 0;

  for (const patch of patches) {
    const candidates = patch.matchField === "name"
      ? updatedVariants.filter((v) => cleanVariantNameForMatch(v.name) === patch.matchValue)
      : updatedVariants.filter((v) => textValue(v[patch.matchField]) === patch.matchValue);

    if (candidates.length !== 1) {
      reappliedSkipped.push({
        name: patch.name,
        reason: candidates.length === 0 ? "not_found_in_latest" : "ambiguous_in_latest",
      });
      continue;
    }

    candidates[0].image = patch.image;
    candidates[0].imageUrl = patch.imageUrl;
    appliedCount += 1;
  }

  return { updatedVariants, appliedCount, reappliedSkipped };
}

module.exports = { computeVariantImagePatches, applyVariantImagePatchesToLatest };
