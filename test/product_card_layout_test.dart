import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/widgets/product_card.dart';

// Worst cases taken from the live catalog (2026-11-11). Images are left
// empty so the test never touches the network.
const longestTitle =
    'AAA+++ OLED For iPhone X XR Max XS LCD Incell For iphone 11 12 13 Pro Max '
    '13 Mini 14 Plus OLED Display Screen Digitizer Assembly';
const highestPriceTitle =
    'Fully Tested 100% Working Motherboard For iPhone 17ProMax Mainboard With '
    'Face ID Unlocked And Cleaned iCloud Pysical SIM Version';

Map<String, dynamic> product(
  String id,
  String name,
  num price,
  num mrp, {
  String manufacturer = 'Generic',
}) =>
    {
      'id': id,
      'name': name,
      'manufacturer': manufacturer,
      'image': '',
      'isActive': true,
      'variants': [
        {'name': 'Default', 'price': price, 'mrp': mrp, 'stock': 5},
      ],
    };

final worstCases = <String, Map<String, dynamic>>{
  'longest title': product('T5fPnBIl5fIKT0TSXpw4', longestTitle, 1850, 2050),
  'highest price': product('imp_aliexpress_3eb4', highestPriceTitle, 94780, 137363),
  'lowest price, MRP 0': product('hcYlLXrkn9kgDj9Q30k6', 'SMC Orsaline-N Oral Rehydration Solution', 6, 0),
  'no discount': product('9IQpLrrF3L8lPkyJysy8', 'AirPods Pro 2nd Generation Bluetooth Earbuds - Waterproof', 699, 699),
  'no manufacturer': product('nomfr', 'Short', 120, 150, manufacturer: ''),
  // Real fractional prices that overlapped the add button on desktop.
  'fractional price': product('frac', 'AMD Ryzen 3 2200G R3 2200G PRO 2200GE', 3708.71, 10024.37),
  // 5-digit "from" price + MRP that overlapped "+" at 360px (2026-11-15).
  'from 24,452 / 35,438': fromProduct('from5', 'Netac SSD 1TB 2TB 4TB 128GB 256GB 512GB SSD SATA', 24452, 35438),
  'from 62,477 / 99,999': fromProduct('from6', highestPriceTitle, 62477, 99999),
};

/// A product whose variants cost different amounts ("৳X থেকে").
Map<String, dynamic> fromProduct(String id, String name, num price, num mrp) => {
      'id': id,
      'name': name,
      'manufacturer': 'Netac',
      'image': '',
      'isActive': true,
      'variants': [
        {'name': 'A', 'price': price, 'mrp': mrp, 'stock': 5},
        {'name': 'B', 'price': price * 2, 'mrp': mrp * 2, 'stock': 5},
      ],
    };

/// Rects of the add buttons and of every price/MRP text inside each card.
void expectAddButtonsClearOfText(WidgetTester tester) {
  for (final card in find.byType(ProductCard).evaluate()) {
    final cardFinder = find.byWidget(card.widget);
    final button = tester.getRect(find.descendant(of: cardFinder, matching: find.byIcon(Icons.add)));
    final texts = find.descendant(
      of: cardFinder,
      matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('৳')),
    );
    for (final t in texts.evaluate()) {
      final r = tester.getRect(find.byWidget(t.widget).first);
      expect(r.right, lessThanOrEqualTo(button.left + 0.5),
          reason: '"${(t.widget as RichText).text.toPlainText()}" reaches into "+"');
    }
  }
}

/// Homepage row: a fixed-height horizontal list of fixed-width cards.
Widget homepageRow(double textScale) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(2000, 800), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Builder(
            builder: (context) => SizedBox(
              height: ProductCard.rowHeight(context),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [for (final p in worstCases.values) ProductCard(data: p)],
              ),
            ),
          ),
        ),
      ),
    );

/// Category/search/wishlist grid at a given screen width.
Widget grid(double width, int columns, double textScale) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Builder(
            builder: (context) => GridView(
              padding: const EdgeInsets.symmetric(horizontal: ProductCard.gridHorizontalPadding),
              gridDelegate: ProductCard.gridDelegate(context, crossAxisCount: columns),
              children: [for (final p in worstCases.values) ProductCard(data: p, gridMode: true)],
            ),
          ),
        ),
      ),
    );

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('homepage row: worst cases fit, no overflow (text x$scale)', (tester) async {
      tester.view.physicalSize = const Size(2000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(homepageRow(scale));
      expect(tester.takeException(), isNull);
      expect(find.byType(ProductCard), findsNWidgets(worstCases.length));
    });

    for (final (label, width, columns) in [
      ('320px', 320.0, 2),
      ('360px', 360.0, 2),
      ('375px', 375.0, 2),
      ('1366px', 1366.0, 6),
    ]) {
      testWidgets('$label grid: worst cases fit, no overflow, "+" clear of text (text x$scale)', (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(grid(width, columns, scale));
        expect(tester.takeException(), isNull);
        expectAddButtonsClearOfText(tester);
      });
    }

    testWidgets('row: "+" clear of text and every card the same height, MRP or not (text x$scale)', (tester) async {
      tester.view.physicalSize = const Size(2400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(homepageRow(scale));
      expect(tester.takeException(), isNull);
      expectAddButtonsClearOfText(tester);
      final heights = {
        for (final c in find.byType(ProductCard).evaluate()) tester.getSize(find.byWidget(c.widget)).height,
      };
      expect(heights, hasLength(1));
    });
  }

  testWidgets('prices are formatted and the discount badge shows only with a discount', (tester) async {
    // Wide enough that the horizontal list builds every card.
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(homepageRow(1.0));
    expect(find.text('৳94,780'), findsOneWidget);
    expect(find.text('-31%'), findsNWidgets(2)); // 94,780/137,363 and 24,452/35,438
    expect(find.text('-38%'), findsOneWidget); // 62,477/99,999
    expect(find.text('-10%'), findsOneWidget); // ৳1,850 vs ৳2,050
    expect(find.text('৳699'), findsOneWidget);
    expect(find.text('৳6'), findsOneWidget);
    expect(find.textContaining('.00'), findsNothing);
    // Exactly six badges (-31% x2, -38%, -10%, -20%, -63%): none for the no-discount and
    // MRP-0 products. Matched exactly, since a title contains "100%".
    final badge = RegExp(r'^-\d+%$');
    expect(
      find.byWidgetPredicate((w) => w is Text && badge.hasMatch(w.data ?? '')),
      findsNWidgets(6),
    );
    expect(find.text('-20%'), findsOneWidget); // ৳120 vs ৳150
  });

  testWidgets('price on line 1, struck-out MRP on line 2, "+" to the right of both', (tester) async {
    tester.view.physicalSize = const Size(2400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(homepageRow(1.0));
    expect(tester.takeException(), isNull);
    final price = tester.getRect(find.text('৳24,452 থেকে'));
    final mrp = tester.getRect(find.text('৳35,438'));
    expect(mrp.top, greaterThanOrEqualTo(price.bottom - 0.5));
    final card = find.ancestor(of: find.text('৳35,438'), matching: find.byType(ProductCard));
    final button = tester.getRect(find.descendant(of: card, matching: find.byIcon(Icons.add)));
    expect(button.left, greaterThanOrEqualTo(price.right));
    expect(button.left, greaterThanOrEqualTo(mrp.right));
    expect(find.text('৳10,024'), findsOneWidget);
  });

  testWidgets('row card height is exactly the computed content height', (tester) async {
    // Wide enough that the horizontal list builds every card.
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(homepageRow(1.0));
    final context = tester.element(find.byType(ProductCard).first);
    // The card's outer Container includes its 4 + 8 vertical margin, so it
    // fills the row exactly: no empty band under the price row.
    final outer = tester.getSize(find.descendant(
      of: find.byType(ProductCard).first,
      matching: find.byType(Container),
    ).first);
    expect(ProductCard.rowHeight(context), ProductCard.cardHeight(context) + 12);
    expect(outer.height, ProductCard.rowHeight(context));
    // The price block (line 2 = MRP) sits at the bottom of the card, 8px
    // above its edge.
    final cardRect = tester.getRect(find.byType(ProductCard).first);
    final mrpRect = tester.getRect(find.text('৳2,050'));
    expect(cardRect.bottom - 8 - 8 - mrpRect.bottom, lessThan(8));
  });
}
