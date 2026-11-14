// Checks every bundled category SVG actually draws in both brand colours.
// Uses no dart:io, so it also runs on the web engine:
//   flutter test --platform chrome test/category_icons_render_test.dart
import 'dart:ui' as ui;

import 'package:chalakchar_mart/widgets/home_category_grid.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const icons = [
  CategoryFallbackIcon.computerAccessories,
  CategoryFallbackIcon.mobileParts,
  CategoryFallbackIcon.motherboard,
  CategoryFallbackIcon.generic,
];

bool near(int r, int g, int b, int tr, int tg, int tb) =>
    (r - tr).abs() < 12 && (g - tg).abs() < 12 && (b - tb).abs() < 12;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final asset in icons) {
    test('$asset renders navy and orange', () async {
      final svg = await rootBundle.loadString(asset);
      final info = await vg.loadPicture(SvgStringLoader(svg), null);
      expect(info.size, const ui.Size(96, 96));

      final image = await info.picture.toImage(96, 96);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var navy = 0, orange = 0, transparentCorner = bytes.getUint8(3) == 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint8(i + 3) < 250) continue;
        final r = bytes.getUint8(i), g = bytes.getUint8(i + 1), b = bytes.getUint8(i + 2);
        if (near(r, g, b, 0x23, 0x2F, 0x3E)) navy++;
        if (near(r, g, b, 0xFF, 0x99, 0x00)) orange++;
      }
      expect(navy, greaterThan(100), reason: 'navy strokes missing');
      expect(orange, greaterThan(20), reason: 'orange accent missing');
      expect(transparentCorner, isTrue, reason: 'background must be transparent');
    });
  }
}
