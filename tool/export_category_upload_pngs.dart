// Exports the bundled category SVG icons as 512x512 transparent PNGs, ready
// to upload through Manage Categories. Rendered by flutter_svg itself, so the
// PNGs match what the app draws for the fallback icons.
//
// Run: flutter test tool/export_category_upload_pngs.dart
// Output: design/category_upload/<icon>.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 512;
const _paddingFraction = 0.05;

const _icons = {
  'computer_accessories': 'assets/icons/category_computer_accessories.svg',
  'mobile_parts': 'assets/icons/category_mobile_parts.svg',
  'motherboard': 'assets/icons/category_motherboard.svg',
  'generic': 'assets/icons/category_generic.svg',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export category upload PNGs', () async {
    final outDir = Directory('design/category_upload')..createSync(recursive: true);

    for (final entry in _icons.entries) {
      final svg = await rootBundle.loadString(entry.value);
      final info = await vg.loadPicture(SvgStringLoader(svg), null);

      const inner = _size * (1 - 2 * _paddingFraction);
      final scale = inner / (info.size.width > info.size.height
          ? info.size.width
          : info.size.height);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.translate(
        (_size - info.size.width * scale) / 2,
        (_size - info.size.height * scale) / 2,
      );
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
      info.picture.dispose();

      final image = await recorder.endRecording().toImage(_size, _size);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${outDir.path}/category_${entry.key}.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      expect(image.width, _size);
      expect(image.height, _size);
    }
  });
}
