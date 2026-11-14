// Worst-case layout checks for the desktop "Product Categories" grid, with
// mock data only (no Firestore, no network).
//
// Set SCREENSHOT_DIR to also write a PNG per case and width:
//   SCREENSHOT_DIR=<dir> flutter test test/home_category_grid_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chalakchar_mart/services/category_service.dart';
import 'package:chalakchar_mart/widgets/home_category_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

CategoryModel cat(String name, [String imageUrl = '']) => CategoryModel(
      id: name,
      name: name,
      description: '',
      imageUrl: imageUrl,
      priority: 0,
      isActive: true,
      isFeatured: false,
      showOnHome: true,
    );

const realThree = ['Computer Accessories', 'Mobile Parts', 'Motherboard'];
const longName = 'Computer Accessories & Networking Equipment';

final cases = <String, List<CategoryModel>>{
  'a_current_3': [for (final n in realThree) cat(n)],
  'b_one_category': [cat('Mobile Parts')],
  'c_14_categories': [
    for (final n in [
      'Computer Accessories', 'Mobile Parts', 'Motherboard', 'Laptops',
      'Phone Cases', 'Smart Watches', 'Chargers & Cables', 'Headphones',
      'Mainboard ICs', 'Gaming Keyboards', 'Toys', 'Jewellery',
      'Kitchen Appliances', 'Flex Cable',
    ])
      cat(n),
  ],
  'd_long_name': [cat(longName), cat('Mobile Parts'), cat('Motherboard')],
  'e_missing_and_broken_image': [
    cat('Computer Accessories'), // no imageUrl
    cat('Mobile Parts', 'mock://corrupt'), // bytes that fail to decode
    cat('Motherboard', 'https://example.invalid/404.png'), // HTTP error
  ],
  'f_wide_and_tall_image': [
    cat('Wide Banner Upload', 'mock://wide'),
    cat('Tall Poster Upload', 'mock://tall'),
    cat('Motherboard'),
  ],
  'g_uploaded_pngs': [
    for (final n in realThree)
      cat(n, 'mock://upload/${n.toLowerCase().replaceAll(' ', '_')}'),
  ],
};

/// Sizes the screenshots are taken at. Desktop is the real web layout
/// (260px sidebar + 24/40px padding); narrower widths render the grid on its
/// own with a 16px gutter as an adaptability check.
const widths = {
  'desktop_2560': 2560.0,
  'desktop_1920': 1920.0,
  'desktop_1440': 1440.0,
  'tablet_768': 768.0,
  'mobile_375': 375.0,
};

final mockImages = <String, Uint8List>{};

Future<Uint8List> _drawTestImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final rect = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFF32A8C7));
  canvas.drawRect(
    rect.deflate(6),
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = const ui.Color(0xFF232F3E),
  );
  // A circle shows any stretching at a glance.
  final r = (w < h ? w : h) * 0.35;
  canvas.drawCircle(rect.center, r, ui.Paint()..color = const ui.Color(0xFFFF9900));
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

ImageProvider mockProvider(String url) {
  if (url.startsWith('mock://')) {
    return MemoryImage(mockImages[url] ?? Uint8List.fromList([1, 2, 3, 4]));
  }
  return NetworkImage(url); // flutter_test answers every request with 400.
}

Future<void> loadFont(String family, List<String> files) async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final loader = FontLoader(family);
  var any = false;
  for (final f in files) {
    final file = File('$root/bin/cache/artifacts/material_fonts/$f');
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    any = true;
  }
  if (any) await loader.load();
}

Widget section(List<CategoryModel> categories, double width) {
  final grid = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Product Categories',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          TextButton(
            onPressed: () {},
            child: const Text(
              'See All',
              style: TextStyle(color: Color(0xFF32A8C7), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      HomeCategoryGrid(
        key: const Key('grid'),
        categories: categories,
        onTap: (_) {},
        imageProviderFor: mockProvider,
      ),
    ],
  );

  final body = width >= 1024
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 260,
              height: 420,
              padding: const EdgeInsets.fromLTRB(40, 30, 0, 30),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                alignment: Alignment.center,
                child: const Text('sidebar\n(unchanged)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black38)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 30, 40, 30),
                child: grid,
              ),
            ),
          ],
        )
      : Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 24), child: grid);

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'Roboto'),
    home: Scaffold(
      backgroundColor: const Color(0xFFF8FBFB),
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: const Key('shot'),
          child: ColoredBox(color: const Color(0xFFF8FBFB), child: body),
        ),
      ),
    ),
  );
}

void main() {
  final shotDir = Platform.environment['SCREENSHOT_DIR'];

  setUpAll(() async {
    await loadFont('Roboto', [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
    ]);
    mockImages['mock://wide'] = await _drawTestImage(1600, 200);
    mockImages['mock://tall'] = await _drawTestImage(200, 1600);
    for (final n in realThree) {
      final key = n.toLowerCase().replaceAll(' ', '_');
      final file = File('design/category_upload/category_$key.png');
      if (file.existsSync()) {
        mockImages['mock://upload/$key'] = file.readAsBytesSync();
      }
    }
  });

  test('fallback icon picks by category name', () {
    expect(CategoryFallbackIcon.assetFor('Computer Accessories'),
        CategoryFallbackIcon.computerAccessories);
    expect(CategoryFallbackIcon.assetFor('Mobile Parts'),
        CategoryFallbackIcon.mobileParts);
    expect(CategoryFallbackIcon.assetFor('Motherboard'),
        CategoryFallbackIcon.motherboard);
    expect(CategoryFallbackIcon.assetFor('Toys'), CategoryFallbackIcon.generic);
  });

  test('column count', () {
    expect(HomeCategoryGrid.columnsFor(3, 1116), 3);
    expect(HomeCategoryGrid.columnsFor(1, 1116), 1);
    expect(HomeCategoryGrid.columnsFor(14, 1116), 7);
    expect(HomeCategoryGrid.columnsFor(14, 343), 3);
    expect(HomeCategoryGrid.columnsFor(2, 343), 3);
    expect(HomeCategoryGrid.cardWidthFor(3, 2236), HomeCategoryGrid.maxCardWidth);
    expect(HomeCategoryGrid.cardWidthFor(14, 1116), lessThan(HomeCategoryGrid.maxCardWidth));
  });

  for (final c in cases.entries) {
    for (final w in widths.entries) {
      testWidgets('${c.key} @ ${w.key}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w.value, 1400);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(section(c.value, w.value));
        // Let SVG assets and images decode, then the 200ms fade-in finish.
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);

        final cards = find.descendant(
          of: find.byKey(const Key('grid')),
          matching: find.byType(AnimatedContainer),
        );
        expect(cards, findsNWidgets(c.value.length));

        // Square image tiles of equal size.
        final tiles = find.descendant(
          of: cards,
          matching: find.byWidgetPredicate((wd) =>
              wd is Container && wd.decoration is BoxDecoration &&
              (wd.decoration! as BoxDecoration).color == const Color(0xFFEFF7FA)),
        );
        final tileSizes = tiles.evaluate().map((e) => e.size!).toSet();
        expect(tileSizes, hasLength(1));
        expect(tileSizes.single.width, tileSizes.single.height);

        // Cards and tiles stay capped; the first card lines up with the
        // section title on the left.
        expect(tileSizes.single.width,
            lessThanOrEqualTo(HomeCategoryGrid.maxTileSize));
        final gridBox = tester.getRect(find.byKey(const Key('grid')));
        expect(tester.getRect(cards.first).left, closeTo(gridBox.left, 0.5));
        for (final e in cards.evaluate()) {
          expect(e.size!.width,
              lessThanOrEqualTo(HomeCategoryGrid.maxCardWidth + 0.01));
        }

        // Every card shows either a decoded image or the SVG icon, never a
        // broken-image glyph.
        final images = find.descendant(of: cards, matching: find.byType(RawImage));
        final drawn = images
            .evaluate()
            .where((e) => (e.widget as RawImage).image != null)
            .length;
        final svgs =
            find.descendant(of: cards, matching: find.byType(SvgPicture)).evaluate().length;
        expect(drawn + svgs, c.value.length);
        expect(find.byIcon(Icons.broken_image), findsNothing);

        // Names stay within two lines.
        for (final t in find
            .descendant(of: cards, matching: find.byType(Text))
            .evaluate()) {
          expect((t.widget as Text).maxLines, 2);
        }

        if (shotDir != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('shot')));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1.5);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$shotDir/${c.key}__${w.key}.png');
            await file.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
          });
        }
      });
    }
  }
}
