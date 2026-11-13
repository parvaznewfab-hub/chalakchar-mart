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
};

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

    for (final (label, width, columns) in [('mobile', 360.0, 2), ('desktop', 1280.0, 6)]) {
      testWidgets('$label grid: worst cases fit, no overflow (text x$scale)', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(grid(width, columns, scale));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('prices are formatted and the discount badge shows only with a discount', (tester) async {
    // Wide enough that the horizontal list builds every card.
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(homepageRow(1.0));
    expect(find.text('৳94,780'), findsOneWidget);
    expect(find.text('-31%'), findsOneWidget);
    expect(find.text('-10%'), findsOneWidget); // ৳1,850 vs ৳2,050
    expect(find.text('৳699'), findsOneWidget);
    expect(find.text('৳6'), findsOneWidget);
    expect(find.textContaining('.00'), findsNothing);
    // Exactly four badges (-31%, -10%, -20%, -63%): none for the no-discount and
    // MRP-0 products. Matched exactly, since a title contains "100%".
    final badge = RegExp(r'^-\d+%$');
    expect(
      find.byWidgetPredicate((w) => w is Text && badge.hasMatch(w.data ?? '')),
      findsNWidgets(4),
    );
    expect(find.text('-20%'), findsOneWidget); // ৳120 vs ৳150
  });

  testWidgets('MRP that does not fit is dropped; badge and price stay inside the row', (tester) async {
    // Wide enough that the horizontal list builds every card.
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(homepageRow(1.0));
    expect(tester.takeException(), isNull);
    expect(find.text('৳3,708.71'), findsOneWidget);
    expect(find.text('-63%'), findsOneWidget);
    expect(find.text('৳10,024.37'), findsNothing);
    // The price never reaches into the add button.
    final card = find.ancestor(of: find.text('৳3,708.71'), matching: find.byType(ProductCard));
    final button = find.descendant(of: card, matching: find.byIcon(Icons.add));
    expect(tester.getRect(find.text('৳3,708.71')).right,
        lessThanOrEqualTo(tester.getRect(button).left));
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
    // The price row sits at the bottom of the card, 8px above its edge.
    final cardRect = tester.getRect(find.byType(ProductCard).first);
    final priceRect = tester.getRect(find.text('৳1,850'));
    expect(cardRect.bottom - 8 - 8 - priceRect.bottom, lessThan(8));
  });
}
