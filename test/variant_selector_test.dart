import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/widgets/variant_selector.dart';

// 7 storage variants that all reuse one product photo, one out of stock —
// the shape AliExpress SSD/phone listings arrive in.
const sharedImage = 'https://example.com/same.jpg';
Map<String, dynamic> storageProduct() => {
      'id': 'ssd',
      'name': 'Portable SSD',
      'imageUrl': sharedImage,
      'variants': [
        for (final (name, price, stock) in [
          ('128GB', 1200, 5),
          ('256GB', 1800, 5),
          ('512GB', 2600, 0), // out of stock
          ('1TB', 4100, 3),
          ('2TB', 7400, 2),
          ('4TB', 13900, 1),
          ('8TB | China Mainland', 25900, 1),
        ])
          {
            'name': name,
            'price': price,
            'mrp': price,
            'stock': stock,
            'imageUrl': sharedImage,
            // AliExpress's own name — stored for reference, never shown.
            'sourceAttributeName': 'SSD Capacity',
          },
      ],
    };

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

Widget harness(Map<String, dynamic> data, String selected,
    ValueChanged<String> onSelect, double width) {
  // Mobile: full width minus the page's 14px gutters. Desktop: the middle
  // column of the 35/35/30 three-column layout.
  final columnWidth = width < 800 ? width - 28 : (width - 48 - 56) * 0.35;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    // Same fallback as the app theme (lib/main.dart) so ৳ renders.
    theme: ThemeData(fontFamilyFallback: const ['TakaFallback']),
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: const Key('shot'),
          child: Container(
            color: Colors.white,
            width: columnWidth,
            padding: const EdgeInsets.all(8),
            child: VariantSelector(
                data: data, selectedUnit: selected, onSelect: onSelect),
          ),
        ),
      ),
    ),
  );
}

Finder chipFinder() => find.byWidgetPredicate((x) =>
    x.key is ValueKey &&
    '${(x.key as ValueKey).value}'.startsWith('variant-chip-'));

Future<void> shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SCREENSHOT_DIR'];
  if (dir == null) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  });
}

void main() {
  final shotDir = Platform.environment['SCREENSHOT_DIR'];
  setUpAll(() async {
    await loadFont(
        'Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']);
    // The app's bundled Taka-sign font (pubspec `fonts:`).
    final taka = FontLoader('TakaFallback');
    for (final f in [
      'assets/fonts/NotoSansBengaliTaka-Regular.ttf',
      'assets/fonts/NotoSansBengaliTaka-Bold.ttf',
    ]) {
      taka.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await taka.load();
  });

  for (final w in {'mobile_375': 375.0, 'desktop_1440': 1440.0}.entries) {
    testWidgets('shared-image storage variants @ ${w.key}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(w.value, 900);
      addTearDown(tester.view.reset);

      var selected = '128GB';
      final taps = <String>[];
      final data = storageProduct();
      await tester.pumpWidget(harness(data, selected, (n) {
        taps.add(n);
        selected = n;
      }, w.value));
      await tester.pump();
      expect(tester.takeException(), isNull); // no overflow

      // 1. Text chips, not identical image swatches.
      expect(find.byWidgetPredicate((x) =>
          x.key is ValueKey && '${(x.key as ValueKey).value}'.startsWith('variant-swatch-')),
          findsNothing);
      expect(find.byWidgetPredicate((x) =>
          x.key is ValueKey && '${(x.key as ValueKey).value}'.startsWith('variant-chip-')),
          findsNWidgets(7));
      expect(find.byType(Image), findsNothing);
      // Per-variant price shown because prices differ.
      expect(find.text('৳13,900'), findsOneWidget);
      // Shipping-origin suffix is hidden.
      expect(find.text('8TB'), findsOneWidget);

      // 2. Label inferred from the values (not AliExpress's "SSD Capacity").
      final label = tester.widget<Text>(find.byKey(const Key('variant-label')));
      expect(label.textSpan!.toPlainText(), 'Capacity: 128GB');
      expect(find.textContaining('Color'), findsNothing);

      // 3. Out-of-stock: struck through, greyed, still tappable.
      final oos = tester.widget<Text>(find.text('512GB'));
      expect(oos.style!.decoration, TextDecoration.lineThrough);
      expect(oos.style!.color, Colors.grey.shade500);
      final inStock = tester.widget<Text>(find.text('256GB'));
      expect(inStock.style!.decoration, isNull);

      await tester.tap(find.text('512GB'));
      expect(taps, ['512GB']);
      await tester.pumpWidget(harness(data, selected, (_) {}, w.value));
      expect(
          tester
              .widget<Text>(find.byKey(const Key('variant-label')))
              .textSpan!
              .toPlainText(),
          'Capacity: 512GB  (Out of stock)');

      // Every chip fits inside the column.
      final column = tester.getRect(find.byType(VariantSelector));
      for (final e in find
          .byWidgetPredicate((x) => x.key is ValueKey &&
              '${(x.key as ValueKey).value}'.startsWith('variant-chip-'))
          .evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        expect(r.right, lessThanOrEqualTo(column.right + 0.01));
        expect(r.height, greaterThanOrEqualTo(40)); // tap target
      }

      if (shotDir != null) {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$shotDir/variant_selector__${w.key}.png');
          await file.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List());
        });
      }
    });
  }

  testWidgets('storage sizes ascend; real Netac order 4TB,512GB,...',
      (tester) async {
    final netac = {
      'variants': [
        for (final n in ['4TB', '512GB', '256GB', '2TB', '1TB', '128GB'])
          {'name': '$n Black / China Mainland', 'price': 1000, 'stock': 3},
      ],
    };
    for (final w in [375.0, 1440.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(w, 900);
      await tester.pumpWidget(harness(netac, '4TB Black / China Mainland', (_) {}, w));
      await tester.pump();
      final order = [
        for (final e in chipFinder().evaluate())
          ('${(e.widget.key as ValueKey).value}', tester.getTopLeft(find.byWidget(e.widget))),
      ]..sort((a, b) => a.$2.dy != b.$2.dy
          ? a.$2.dy.compareTo(b.$2.dy)
          : a.$2.dx.compareTo(b.$2.dx));
      expect(order.map((e) => e.$1.split('-').last.split(' ').first).toList(),
          ['128GB', '256GB', '512GB', '1TB', '2TB', '4TB'],
          reason: 'width $w');
    }
    tester.view.reset();
  });

  for (final w in [800.0, 1000.0]) {
    testWidgets('desktop ${w.toInt()}px: short text chips 2 per row, not full width',
        (tester) async {
      final netac = {
        'variants': [
          for (final (n, p) in [('4TB', 47546), ('512GB', 7606), ('256GB', 4481),
              ('2TB', 24451), ('1TB', 13583), ('128GB', 2851)])
            {'name': '$n Black / China Mainland', 'price': p, 'stock': 3},
        ],
      };
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(w, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(netac, '128GB Black / China Mainland', (_) {}, w));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final column = tester.getRect(find.byType(VariantSelector));
      final rects = [for (final e in chipFinder().evaluate()) tester.getRect(find.byWidget(e.widget))];
      expect(rects, hasLength(6));
      for (final r in rects) {
        expect(r.width, lessThan(column.width / 2), reason: 'chip is not full width');
      }
      expect(rects.map((r) => r.top).toSet(), hasLength(3)); // 2 per row
      await shot(tester, 'variant_text_chips__desktop_${w.toInt()}');
    });
  }

  String labelText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('variant-label')))
      .textSpan!
      .toPlainText();

  testWidgets('AliExpress "Color" on model names is not shown',
      (tester) async {
    // Real data: a Huawei board listed with phone models under "Color".
    final data = {
      'variants': [
        for (final m in ['Nova 3i', 'Nova 3E', 'Nova 3'])
          {
            'name': '$m / China Mainland',
            'price': 900,
            'stock': 3,
            'sourceAttributeName': 'Color',
          },
      ],
    };
    await tester.pumpWidget(harness(data, 'Nova 3i / China Mainland', (_) {}, 375));
    expect(labelText(tester), 'Option: Nova 3i');
  });

  testWidgets('manual variantAttributeName wins', (tester) async {
    await tester.pumpWidget(harness(
        {...storageProduct(), 'variantAttributeName': 'Drive size'},
        '1TB', (_) {}, 375));
    expect(labelText(tester), 'Drive size: 1TB');
  });

  testWidgets('distinct variant images keep image swatches', (tester) async {
    final data = {
      'variants': [
        {'name': 'Red', 'price': 100, 'stock': 2, 'imageUrl': 'https://x/r.jpg'},
        {'name': 'Blue', 'price': 100, 'stock': 0, 'imageUrl': 'https://x/b.jpg'},
      ],
    };
    await tester.pumpWidget(harness(data, 'Red', (_) {}, 1440));
    await tester.pump();
    expect(find.byKey(const ValueKey('variant-swatch-Red')), findsOneWidget);
    expect(find.byKey(const ValueKey('variant-swatch-Blue')), findsOneWidget);
    // Picture options always carry their value as text too.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('variant-swatch-Red')),
            matching: find.text('Red')),
        findsOneWidget);
    // Same price everywhere -> no per-variant price clutter.
    expect(find.text('৳100'), findsNothing);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('variant-label')))
            .textSpan!
            .toPlainText(),
        'Color: Red'); // values are real colours
  });
  group('picture options (motherboard: 17 look-alike images)', () {
    // Real names/stock from imp_aliexpress_390a856c… (one out of stock).
    const names = [
      '15 256g No Face ID', '15 128g Face ID', '15Pro 128g No Face',
      '15Pro 256g No Face', '15Pro 1TB Face ID', '15 256g Face ID',
      '15Plus 128g No Face', '15PM 512g No Face', '15Plus 256g No Face',
      '15PM 256 No Face', '15Plus 128g Face ID', '15Plus 256g Face ID',
      '15PM 256g Face ID', '15Pro 256g Face ID', '15Pro 128g Face ID',
      '15 128g No Face ID', '15PM 512g Face ID',
    ];
    Map<String, dynamic> board() => {
          'variants': [
            for (var i = 0; i < names.length; i++)
              {
                'name': names[i],
                'price': 20000 + i * 1500,
                'stock': names[i] == '15Pro 1TB Face ID' ? 0 : 5,
                'imageUrl': 'https://x/board_$i.jpg', // distinct URLs
              },
          ],
        };
    final pictureChip = find.byWidgetPredicate((x) =>
        x.key is ValueKey &&
        '${(x.key as ValueKey).value}'.startsWith('variant-swatch-'));

    testWidgets('375px: thumbnail + value, 2 per row, even cells, +N more',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(board(), names.first, (_) {}, 375));
      await tester.pump();
      expect(tester.takeException(), isNull); // no overflow

      // Two rows of two: 3 options + "+14 more".
      expect(pictureChip, findsNWidgets(3));
      expect(find.text('+14 more'), findsOneWidget);
      final rects = [
        for (final e in pictureChip.evaluate()) tester.getRect(find.byWidget(e.widget)),
        tester.getRect(find.byKey(const Key('variant-more'))),
      ];
      expect(rects.map((r) => r.top).toSet(), hasLength(2));
      expect(rects.map((r) => r.size).toSet(), hasLength(1)); // even grid
      // Value text is visible in every picture option.
      for (final n in names.take(3)) {
        expect(find.descendant(of: pictureChip, matching: find.text(n)), findsOneWidget);
      }
      await shot(tester, 'variant_pictures__mobile_375_collapsed');

      await tester.tap(find.text('+14 more'));
      await tester.pump();
      expect(pictureChip, findsNWidgets(17));
      expect(tester.takeException(), isNull);
      // Out-of-stock picture option: value struck through.
      final oos = tester.widget<Text>(find.text('15Pro 1TB Face ID'));
      expect(oos.style!.decoration, TextDecoration.lineThrough);
      await shot(tester, 'variant_pictures__mobile_375_expanded');
    });

    testWidgets('each option and the toggle expose exactly one label',
        (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(board(), names.first, (_) {}, 375));
      await tester.pump();
      expect(find.bySemanticsLabel('+14 more'), findsOneWidget);
      expect(find.bySemanticsLabel('15 128g Face ID · ৳21,500'), findsOneWidget);
      // Not repeated by the tooltip or the visible text.
      expect(find.bySemanticsLabel(RegExp('15 128g Face ID.*15 128g Face ID')),
          findsNothing);
      handle.dispose();
    });

    testWidgets('1440px: 2 per row, 3 rows, then "+N more"', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(board(), names.first, (_) {}, 1440));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(pictureChip, findsNWidgets(5));
      expect(find.text('+12 more'), findsOneWidget);
      final rects = [
        for (final e in pictureChip.evaluate()) tester.getRect(find.byWidget(e.widget)),
        tester.getRect(find.byKey(const Key('variant-more'))),
      ];
      expect(rects.map((r) => r.top).toSet(), hasLength(3)); // three rows
      expect(rects.map((r) => r.left).toSet(), hasLength(2)); // two columns
      expect(rects.map((r) => r.size).toSet(), hasLength(1)); // even grid
      expect(tester.getRect(find.byType(VariantSelector)).height, lessThan(320));
      await shot(tester, 'variant_pictures__desktop_1440_collapsed');

      await tester.tap(find.text('+12 more'));
      await tester.pump();
      expect(pictureChip, findsNWidgets(17));
      expect(find.text('Show less'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('800px desktop column: one per row, still 3 rows max',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(board(), names.first, (_) {}, 800));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(pictureChip, findsNWidgets(2));
      expect(find.text('+15 more'), findsOneWidget);
    });
  });

  group('mobile collapse (12 shared-image variants)', () {
    Map<String, dynamic> many() => {
          'variants': [
            for (var i = 1; i <= 12; i++)
              {
                'name': '${i * 64}GB',
                'price': 1000 + i * 100,
                'stock': i == 3 ? 0 : 2,
                'imageUrl': sharedImage,
              },
          ],
        };
    final chip = find.byWidgetPredicate((x) =>
        x.key is ValueKey &&
        '${(x.key as ValueKey).value}'.startsWith('variant-chip-'));

    Set<double> rowTops(WidgetTester tester) => {
          for (final e in chip.evaluate())
            tester.getTopLeft(find.byWidget(e.widget)).dy,
          for (final e in find.byKey(const Key('variant-more')).evaluate())
            tester.getTopLeft(find.byWidget(e.widget)).dy,
        };

    testWidgets('375px: two rows with "+N more", expands and collapses',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 900);
      addTearDown(tester.view.reset);
      var selected = '64GB';
      await tester.pumpWidget(
          harness(many(), selected, (n) => selected = n, 375));
      expect(tester.takeException(), isNull);

      expect(chip, findsNWidgets(7));
      expect(find.text('+5 more'), findsOneWidget);
      expect(rowTops(tester), hasLength(2)); // exactly two rows
      // "+N more" lines up with the chips (same height as a price chip).
      expect(tester.getSize(find.byKey(const Key('variant-more'))).height,
          closeTo(tester.getSize(chip.at(1)).height, 2.5));
      await shot(tester, 'variant_collapse__mobile_375_collapsed');

      await tester.tap(find.text('+5 more'));
      await tester.pump();
      expect(chip, findsNWidgets(12));
      expect(find.text('Show less'), findsOneWidget);
      await shot(tester, 'variant_collapse__mobile_375_expanded');
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Show less'));
      await tester.pump();
      expect(chip, findsNWidgets(7));
    });

    testWidgets('375px: selection past the fold is never hidden',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(many(), '640GB', (_) {}, 375));
      expect(chip, findsNWidgets(12));
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('1440px: desktop shows everything, no toggle',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(many(), '64GB', (_) {}, 1440));
      expect(chip, findsNWidgets(12));
      expect(find.textContaining('more'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
