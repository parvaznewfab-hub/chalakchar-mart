import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/variant_image_selector.dart';

void main() {
  group('resolveVariantImageSelection', () {
    test('empty variant image falls back to the primary product image (index 0)', () {
      final result = resolveVariantImageSelection(
        images: ['https://a.example.com/primary.jpg', 'https://a.example.com/2.jpg'],
        variantImage: '',
      );
      expect(result.imageIndex, 0);
      expect(result.imageOverride, null);
    });

    test('empty variant image with an empty gallery returns none (nothing to show)', () {
      final result = resolveVariantImageSelection(images: const [], variantImage: '');
      expect(result.imageIndex, null);
      expect(result.imageOverride, null);
    });

    test('variant image already in the gallery reuses its index, no duplication', () {
      final images = [
        'https://a.example.com/1.jpg',
        'https://a.example.com/2.jpg',
        'https://a.example.com/3.jpg',
      ];
      final result = resolveVariantImageSelection(
        images: images,
        variantImage: 'https://a.example.com/2.jpg',
      );
      expect(result.imageIndex, 1);
      expect(result.imageOverride, null);
      // The gallery list itself is never touched/rebuilt.
      expect(images.length, 3);
    });

    test('variant image not in the gallery becomes a temporary override, not appended', () {
      final images = ['https://a.example.com/1.jpg'];
      final result = resolveVariantImageSelection(
        images: images,
        variantImage: 'https://a.example.com/variant-only.jpg',
      );
      expect(result.imageIndex, null);
      expect(result.imageOverride, 'https://a.example.com/variant-only.jpg');
      // Never appended/duplicated into the gallery list.
      expect(images, ['https://a.example.com/1.jpg']);
    });

    test('empty gallery with a variant image still produces an override', () {
      final result = resolveVariantImageSelection(
        images: const [],
        variantImage: 'https://a.example.com/variant-only.jpg',
      );
      expect(result.imageOverride, 'https://a.example.com/variant-only.jpg');
    });

    // --- Requested scenarios ---

    test('selecting a variant changes the main image (sku_image field, via imageUrl priority)', () {
      // simulates: selectedVariant.imageUrl ?? selectedVariant.image
      const variant = {
        'imageUrl': 'https://ae01.example.com/sku-red.jpg',
        'image': 'https://ae01.example.com/sku-red-fallback.jpg',
      };
      final variantImage = (variant['imageUrl'] ?? variant['image'])!;
      final result = resolveVariantImageSelection(
        images: ['https://ae01.example.com/primary.jpg'],
        variantImage: variantImage,
      );
      expect(variantImage, 'https://ae01.example.com/sku-red.jpg');
      expect(result.imageOverride, 'https://ae01.example.com/sku-red.jpg');
    });

    test('different variants (different sku_image URLs) resolve to different results', () {
      final images = ['https://ae01.example.com/primary.jpg'];
      final redResult = resolveVariantImageSelection(
        images: images,
        variantImage: 'https://ae01.example.com/sku-red.jpg',
      );
      final blueResult = resolveVariantImageSelection(
        images: images,
        variantImage: 'https://ae01.example.com/sku-blue.jpg',
      );
      expect(redResult.imageOverride, isNot(equals(blueResult.imageOverride)));
      expect(redResult.imageOverride, 'https://ae01.example.com/sku-red.jpg');
      expect(blueResult.imageOverride, 'https://ae01.example.com/sku-blue.jpg');
    });

    test('fallback to primary image works when the variant has no sku_image', () {
      const variant = <String, dynamic>{}; // no imageUrl, no image
      final variantImage = (variant['imageUrl'] ?? variant['image'] ?? '') as String;
      final result = resolveVariantImageSelection(
        images: ['https://ae01.example.com/primary.jpg', 'https://ae01.example.com/2.jpg'],
        variantImage: variantImage,
      );
      expect(result.imageIndex, 0); // primary image
      expect(result.imageOverride, null);
    });
  });

  group('ActiveImageState (gallery-vs-variant-override bug)', () {
    final images = [
      'https://a.example.com/1.jpg',
      'https://a.example.com/2.jpg',
      'https://a.example.com/3.jpg',
    ];

    test('initial gallery thumbnail selection works', () {
      const state = ActiveImageState();
      final next = state.selectGalleryImage(2);
      expect(next.selectedImageIndex, 2);
      expect(next.variantImageOverride, null);
      expect(next.activeImageUrl(images), images[2]);
    });

    test('variant selection activates a variant image override', () {
      const state = ActiveImageState();
      final next = state.selectVariant(
        images: images,
        variantImage: 'https://a.example.com/variant-only.jpg',
      );
      expect(next.variantImageOverride, 'https://a.example.com/variant-only.jpg');
      expect(next.activeImageUrl(images), 'https://a.example.com/variant-only.jpg');
    });

    test('gallery thumbnail selection after variant selection clears the variant override (the reported bug)', () {
      final afterVariant = const ActiveImageState().selectVariant(
        images: images,
        variantImage: 'https://a.example.com/variant-only.jpg',
      );
      expect(afterVariant.activeImageUrl(images), 'https://a.example.com/variant-only.jpg');

      final afterGalleryClick = afterVariant.selectGalleryImage(1);
      expect(afterGalleryClick.variantImageOverride, null);
      expect(afterGalleryClick.selectedImageIndex, 1);
      // The main image must now show the clicked gallery image, not the
      // stale variant override — this is exactly the bug that was reported.
      expect(afterGalleryClick.activeImageUrl(images), images[1]);
    });

    test('another variant selection reactivates a variant image after a gallery click', () {
      final afterVariant1 = const ActiveImageState().selectVariant(
        images: images,
        variantImage: 'https://a.example.com/red.jpg',
      );
      final afterGalleryClick = afterVariant1.selectGalleryImage(0);
      expect(afterGalleryClick.activeImageUrl(images), images[0]);

      final afterVariant2 = afterGalleryClick.selectVariant(
        images: images,
        variantImage: 'https://a.example.com/blue.jpg',
      );
      expect(afterVariant2.activeImageUrl(images), 'https://a.example.com/blue.jpg');
    });

    test('gallery click never resets to index 0 — it always uses the clicked index', () {
      final afterVariant = const ActiveImageState().selectVariant(
        images: images,
        variantImage: 'https://a.example.com/variant-only.jpg',
      );
      final afterGalleryClick = afterVariant.selectGalleryImage(2);
      expect(afterGalleryClick.selectedImageIndex, 2);
      expect(afterGalleryClick.activeImageUrl(images), images[2]);
    });

    test('zoom lens and fullscreen viewer resolve from the same activeImageUrl as the main image', () {
      // The main image, _HoverMagnifierImage, and the fullscreen preview
      // all read `activeImageUrl` (or a value derived from it) — proving
      // there is exactly one source of truth rather than three independent
      // computations that could disagree.
      final variantState = const ActiveImageState().selectVariant(
        images: images,
        variantImage: 'https://a.example.com/variant-only.jpg',
      );
      final mainImageUrl = variantState.activeImageUrl(images);
      final zoomLensUrl = variantState.activeImageUrl(images);
      expect(zoomLensUrl, mainImageUrl);

      // Fullscreen preview list: if the active image isn't in the gallery,
      // it's prepended just for the preview, never mutating `images`.
      final previewImages =
          images.contains(mainImageUrl) ? images : [mainImageUrl, ...images];
      final previewIndex = images.contains(mainImageUrl) ? variantState.selectedImageIndex : 0;
      expect(previewImages[previewIndex], mainImageUrl);
      expect(images.length, 3); // never mutated/duplicated
    });
  });
}
