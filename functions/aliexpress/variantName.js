// -----------------------------------------------------------------------------
// AliExpress SKU/variant display-name resolution.
//
// AliExpress's raw SKU fields mix internal property IDs with human-readable
// text (e.g. sku_code = "14:200004890#11 128g No Face ID;200007763:201336100").
// This module prefers the structured, genuinely human-readable attribute
// fields first, and only falls back to a cleaned raw SKU string — never a
// raw internal property ID — when no readable attribute exists.
// -----------------------------------------------------------------------------

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
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
 * Cleans a raw AliExpress SKU fallback string (sku_name/sku_attr/sku_code).
 * These are often semicolon-separated segments mixing internal property IDs
 * with human-readable text. For each segment:
 *   - a pure "id:id" pair (e.g. "200007763:201336100") is discarded
 *   - text after a "#" (e.g. "14:200004890#11 128g No Face ID" ->
 *     "11 128g No Face ID") is kept
 *   - anything else is kept as-is
 * Surviving segments are joined with " / ". Never returns a raw property ID.
 */
function cleanAliExpressSkuFallbackText(raw) {
  const text = textValue(raw);
  if (!text) return "";

  return text
    .split(";")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      if (/^\d+:\d+$/.test(part)) return ""; // pure internal id pair — discard
      const hashIndex = part.indexOf("#");
      return hashIndex !== -1 ? part.slice(hashIndex + 1).trim() : part;
    })
    .filter(Boolean)
    .join(" / ");
}

/**
 * Resolves the customer-facing display name for one AliExpress SKU object
 * (an entry from ae_item_sku_info_dtos).
 *
 * Priority:
 *   1. ae_sku_property_dtos / sku_property_dtos / properties — per attribute,
 *      preferring property_value_definition_name, then property_value_name,
 *      then sku_property_value, then property_value_display_name; joined
 *      with " / " when there are multiple attributes.
 *   2. Only if no readable attribute value exists: cleaned sku_name, then
 *      cleaned sku_attr, then cleaned sku_code.
 */
function resolveAliExpressVariantName(sku) {
  const item = sku && typeof sku === "object" ? sku : {};
  const attributes = item.ae_sku_property_dtos || item.sku_property_dtos || item.properties;

  if (attributes) {
    const attrArray = aliExpressArray(attributes);
    const fromAttributes = attrArray
      .map((a) => {
        const attr = a && typeof a === "object" ? a : {};
        return textValue(
          attr.property_value_definition_name ||
          attr.property_value_name ||
          attr.sku_property_value ||
          attr.property_value_display_name
        );
      })
      .filter(Boolean)
      .join(" / ");
    if (fromAttributes) return fromAttributes;
  }

  return cleanAliExpressSkuFallbackText(item.sku_name) ||
    cleanAliExpressSkuFallbackText(item.sku_attr) ||
    cleanAliExpressSkuFallbackText(item.sku_code);
}

/**
 * Resolves the human-readable attribute NAME (e.g. "Capacity", "Color",
 * "Size") for one AliExpress SKU — the label for the value that
 * resolveAliExpressVariantName() puts first. The storefront only displays
 * the head of a multi-attribute name (see cleanVariantDisplayName on the
 * client), so the label must describe the first readable attribute.
 * Returns "" when AliExpress didn't send a readable name — callers must not
 * invent one (no "Color" default).
 */
function resolveAliExpressVariantAttributeName(sku) {
  const item = sku && typeof sku === "object" ? sku : {};
  const attributes = item.ae_sku_property_dtos || item.sku_property_dtos || item.properties;
  if (!attributes) return "";

  for (const a of aliExpressArray(attributes)) {
    const attr = a && typeof a === "object" ? a : {};
    const value = textValue(
      attr.property_value_definition_name ||
      attr.property_value_name ||
      attr.sku_property_value ||
      attr.property_value_display_name
    );
    if (!value) continue; // name must belong to the value actually shown
    return textValue(attr.sku_property_name || attr.property_name || attr.attr_name);
  }
  return "";
}

module.exports = {
  cleanAliExpressSkuFallbackText,
  resolveAliExpressVariantName,
  resolveAliExpressVariantAttributeName,
};
