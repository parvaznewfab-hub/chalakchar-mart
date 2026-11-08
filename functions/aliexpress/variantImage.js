// -----------------------------------------------------------------------------
// AliExpress SKU/variant image resolution.
//
// Confirmed field (verified against a live response for this project's
// account): ae_sku_property_dtos[].sku_image. A SKU has multiple properties
// (e.g. Color, Storage) but typically only the visually-distinct one (Color)
// actually carries an image — properties without a visual difference simply
// don't have sku_image populated. So "the property that represents the
// visual variant" is, by construction, whichever property has a non-empty
// sku_image; the first one found is used.
// -----------------------------------------------------------------------------

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function cleanUrl(value) {
  const url = textValue(value);
  return url.startsWith("http://") || url.startsWith("https://") ? url : "";
}

function aliExpressArray(value) {
  if (Array.isArray(value)) return value;
  if (!value || typeof value !== "object") return [];
  for (const child of Object.values(value)) {
    if (Array.isArray(child)) return child;
  }
  return [];
}

/**
 * Resolves the display image for one AliExpress SKU (a variant).
 * Falls back to the product's primary image when no SKU-level image exists,
 * so a variant is never left without an image.
 *
 * @param {object} sku raw SKU object (an entry from ae_item_sku_info_dtos)
 * @param {string} primaryImage the product's primary/main image URL
 * @returns {{ image: string, imageUrl: string }}
 */
function resolveAliExpressVariantImage(sku, primaryImage) {
  const item = sku && typeof sku === "object" ? sku : {};
  const properties = aliExpressArray(item.ae_sku_property_dtos);

  let image = "";
  for (const rawProp of properties) {
    const prop = rawProp && typeof rawProp === "object" ? rawProp : {};
    const candidate = cleanUrl(prop.sku_image);
    if (candidate) {
      image = candidate;
      break;
    }
  }

  if (!image) image = cleanUrl(primaryImage);

  return { image, imageUrl: image };
}

module.exports = { resolveAliExpressVariantImage };
