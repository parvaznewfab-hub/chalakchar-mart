// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/pages/user/product_details_page.dart';
import 'package:chalakchar_mart/services/category_service.dart';

// Real ProductDetailsPage, real VariantSelector: choosing an out-of-stock
// variant must disable Buy Now / Add To Cart and say "Out of Stock".
Map<String, dynamic> product() => {
      'id': 'ssd',
      'name': 'Portable SSD',
      'vendorId': 'super_admin',
      'imageUrl': '',
      'images': <String>[],
      // Manual label (not what the value-based rule would give), proving
      // the page reads it through ProductService normalization.
      'variantAttributeName': 'Storage',
      'variants': [
        for (final (name, stock) in [
          ('128GB', 5),
          ('256GB', 5),
          ('512GB', 0), // out of stock
          ('1TB', 3),
          ('2TB', 2),
          ('4TB', 1),
        ])
          {
            'name': name,
            'price': 1000,
            'mrp': 1000,
            'stock': stock,
            'sourceAttributeName': 'SSD Capacity', // stored, never shown
          },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    // Real metrics instead of the test font (whose wide glyphs overflow the
    // unrelated global header).
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) return;
    final loader = FontLoader('Roboto');
    for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
      final file = File('$root/bin/cache/artifacts/material_fonts/$f');
      if (file.existsSync()) {
        loader.addFont(
            Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
    }
    await loader.load();
  });

  ButtonStyleButton button(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));

  for (final w in {'mobile_375': 375.0, 'desktop_1440': 1440.0}.entries) {
    testWidgets('out-of-stock variant disables purchase @ ${w.key}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(w.value, 2400);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          MaterialApp(home: ProductDetailsPage(data: product())));
      await tester.pump();
      // No layout errors — including the desktop header, which used to
      // declare 136px while laying out 156px (20px overflow).
      expect(tester.takeException(), isNull);

      // In stock to begin with.
      expect(button(tester, 'Buy Now').onPressed, isNotNull);
      expect(button(tester, 'Add To Cart').onPressed, isNotNull);
      expect(find.text('In Stock: 5'), findsOneWidget);

      // Select the out-of-stock variant via the chip.
      await tester.ensureVisible(find.text('512GB').first);
      await tester.tap(find.text('512GB').first);
      await tester.pump();

      expect(button(tester, 'Buy Now').onPressed, isNull);
      expect(button(tester, 'Add To Cart').onPressed, isNull);
      expect(find.text('Out of Stock'), findsOneWidget);
      expect(find.textContaining('(Out of stock)'), findsOneWidget);

      // Picking an in-stock variant re-enables both.
      await tester.ensureVisible(find.text('1TB').first);
      await tester.tap(find.text('1TB').first);
      await tester.pump();
      expect(button(tester, 'Buy Now').onPressed, isNotNull);
      expect(button(tester, 'Add To Cart').onPressed, isNotNull);
      expect(find.text('In Stock: 3'), findsOneWidget);

      // Manual label survives normalization; AliExpress's name isn't shown.
      expect(find.textContaining('Storage: '), findsOneWidget);
      expect(find.textContaining('SSD Capacity'), findsNothing);
    });
  }

  group('default variant when the page opens', () {
    // Stored order as imported (real Netac): 4TB first.
    Map<String, dynamic> netac({int stock128 = 4}) => {
          'id': 'netac',
          'name': 'Netac SSD',
          'vendorId': 'super_admin',
          'variants': [
            for (final (n, p, s) in [('4TB', 47546, 3), ('512GB', 7606, 9),
                ('256GB', 4481, 9), ('2TB', 24451, 9), ('1TB', 13583, 9),
                ('128GB', 2851, stock128)])
              {'name': '$n Black / China Mainland', 'price': p, 'mrp': p, 'stock': s},
          ],
        };

    Future<String> openAndReadLabel(WidgetTester tester, Map<String, dynamic> data) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ProductDetailsPage(data: data)));
      await tester.pump();
      return tester.widget<Text>(find.byKey(const Key('variant-label'))).textSpan!.toPlainText();
    }

    testWidgets('opens on the smallest in-stock size (128GB), not stored 4TB', (t) async {
      expect(await openAndReadLabel(t, netac()), 'Capacity: 128GB Black');
      expect(find.text('In Stock: 4'), findsOneWidget); // price box follows it
    });

    testWidgets('skips an out-of-stock smallest size', (t) async {
      expect(await openAndReadLabel(t, netac(stock128: 0)), 'Capacity: 256GB Black');
    });
  });

  group('category variantLabel defaults on the live page', () {
    // Phone-model values: inference alone would say "Option".
    Map<String, dynamic> board() => {
          'id': 'board',
          'name': 'Mainboard',
          'vendorId': 'super_admin',
          'categoryId': 'cat-motherboard',
          'subcategoryId': 'sub-iphone',
          'variants': [
            for (final n in ['12mini 128g Face ID', '12mini 256g Face ID'])
              {'name': n, 'price': 9000, 'mrp': 9000, 'stock': 2},
          ],
        };

    Future<String> pumpLabel(WidgetTester tester, Map<String, dynamic> data,
        Map<String, String> labels) async {
      CategoryService.debugClearVariantLabelCache();
      CategoryService.debugVariantLabelReader =
          (collection, id) async => labels['$collection/$id'] ?? '';
      addTearDown(() => CategoryService.debugVariantLabelReader = null);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ProductDetailsPage(data: data)));
      await tester.pump(); // labels load
      await tester.pump();
      return tester
          .widget<Text>(find.byKey(const Key('variant-label')))
          .textSpan!
          .toPlainText();
    }

    testWidgets('subcategory default wins over category default', (t) async {
      expect(
          await pumpLabel(t, board(), {
            'subcategories/sub-iphone': 'Board',
            'categories/cat-motherboard': 'Model',
          }),
          'Board: 12mini 128g Face ID');
    });

    testWidgets('category default when the subcategory has none', (t) async {
      expect(
          await pumpLabel(t, board(), {'categories/cat-motherboard': 'Model'}),
          'Model: 12mini 128g Face ID');
    });

    testWidgets('product label wins over both', (t) async {
      expect(
          await pumpLabel(t, {...board(), 'variantAttributeName': 'Logic board'},
              {'categories/cat-motherboard': 'Model'}),
          'Logic board: 12mini 128g Face ID');
    });

    testWidgets('no defaults -> value inference', (t) async {
      expect(await pumpLabel(t, board(), {}), 'Option: 12mini 128g Face ID');
    });
  });
}
