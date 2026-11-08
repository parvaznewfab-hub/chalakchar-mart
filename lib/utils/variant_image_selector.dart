/// Result of resolving which image to show after a variant is selected.
///
/// Exactly one of [imageIndex] (show this index from the product's existing
/// gallery — reuse it as-is, no array mutation needed) or [imageOverride]
/// (the variant image isn't part of the general gallery — show it directly,
/// temporarily, without appending/duplicating it into the gallery) is set.
class VariantImageSelection {
  final int? imageIndex;
  final String? imageOverride;

  const VariantImageSelection({this.imageIndex, this.imageOverride});

  /// No gallery to fall back to at all (e.g. product has zero images).
  static const VariantImageSelection none = VariantImageSelection();
}

/// Decides how to display a selected variant's image without ever
/// duplicating or rebuilding the product's existing image gallery list.
///
/// - Variant has its own image already present in [images]: reuse that
///   index (gallery highlight stays in sync for free).
/// - Variant has its own image NOT present in [images]: show it as a
///   temporary override (never appended/duplicated into the gallery).
/// - Variant has no image of its own: fall back to the primary product
///   image — by this codebase's convention, images[0] — rather than
///   leaving a previously-selected variant's photo on screen.
VariantImageSelection resolveVariantImageSelection({
  required List<String> images,
  required String variantImage,
}) {
  if (variantImage.isEmpty) {
    return images.isEmpty
        ? VariantImageSelection.none
        : const VariantImageSelection(imageIndex: 0);
  }

  final index = images.indexOf(variantImage);
  if (index != -1) {
    return VariantImageSelection(imageIndex: index);
  }
  return VariantImageSelection(imageOverride: variantImage);
}

/// Pure model of the product-details page's "which image is currently
/// active" state — the single source every image-consuming widget (main
/// image, zoom lens, fullscreen viewer) should read from via
/// [activeImageUrl]. Deliberately only models image state: variant/price/
/// stock selection lives elsewhere in the page and is untouched by either
/// transition below.
class ActiveImageState {
  final int selectedImageIndex;
  final String? variantImageOverride;

  const ActiveImageState({
    this.selectedImageIndex = 0,
    this.variantImageOverride,
  });

  /// The URL every image-consuming widget should show — same priority rule
  /// as the main image: an active variant override wins, otherwise the
  /// gallery image at [selectedImageIndex].
  String activeImageUrl(List<String> images) {
    final override = variantImageOverride ?? '';
    if (override.isNotEmpty) return override;
    if (selectedImageIndex >= 0 && selectedImageIndex < images.length) {
      return images[selectedImageIndex];
    }
    return images.isNotEmpty ? images.first : '';
  }

  /// Applies a variant selection: variant image wins when available
  /// (reusing [resolveVariantImageSelection]), otherwise falls back to the
  /// primary gallery image.
  ActiveImageState selectVariant({
    required List<String> images,
    required String variantImage,
  }) {
    final selection = resolveVariantImageSelection(images: images, variantImage: variantImage);
    return ActiveImageState(
      selectedImageIndex: selection.imageIndex ?? selectedImageIndex,
      variantImageOverride: selection.imageOverride,
    );
  }

  /// Applies a direct gallery thumbnail tap: always shows exactly that
  /// index and always clears any active variant override — a gallery click
  /// must never be masked by a stale variant image.
  ActiveImageState selectGalleryImage(int index) {
    return ActiveImageState(selectedImageIndex: index, variantImageOverride: null);
  }
}
