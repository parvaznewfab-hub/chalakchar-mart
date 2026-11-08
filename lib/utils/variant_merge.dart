/// Merges an admin/vendor-edited variant's form fields back into its
/// original Firestore variant map, so metadata the edit form never exposes
/// (image, imageUrl, id, variantId, skuId, sourceSkuId, or anything else)
/// survives a save instead of being silently dropped.
///
/// [original] is the exact variant map the edit row was seeded from (or
/// `null` for a brand-new row added during this edit session — a new
/// variant has nothing to preserve). [editedFields] are the current values
/// of the form-editable fields (name/price/mrp/stock) and always win over
/// whatever was in [original] for those same keys.
Map<String, dynamic> mergeVariantEdit(
  Map<String, dynamic>? original,
  Map<String, dynamic> editedFields,
) {
  return original == null ? editedFields : {...original, ...editedFields};
}
