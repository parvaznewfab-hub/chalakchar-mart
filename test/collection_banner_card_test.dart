import 'package:chalakchar_mart/widgets/collection_banner_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _longTitle =
    'Netac NVMe SSD M2 1TB 2TB 500GB 250GB 3500MB/s SSD PCIe3.0 M.2 2280 '
    'Internal Solid State Drives Disk NV3000 for Laptop Desktop';

List<CollectionBannerItem> _items(int n, {String label = 'Name'}) => [
      for (int i = 0; i < n; i++)
        CollectionBannerItem(imageUrl: '', label: '$label ${i + 1}'),
    ];

Future<void> _pump(WidgetTester tester, Widget card, {double width = 360}) {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Align(alignment: Alignment.topLeft, child: card)),
  ));
}

void main() {
  group('CollectionBannerItem', () {
    test('admin default names count as no name', () {
      expect(CollectionBannerItem.isPlaceholderLabel('Item 1'), isTrue);
      expect(CollectionBannerItem.isPlaceholderLabel(' item 4 '), isTrue);
      expect(CollectionBannerItem.isPlaceholderLabel('Featured item'), isTrue);
      expect(CollectionBannerItem.isPlaceholderLabel('Item 1 Pro'), isFalse);
      expect(CollectionBannerItem.isPlaceholderLabel('SSD'), isFalse);
    });

    test('listFrom hides Item N, drops empty items, keeps at most 4', () {
      final items = CollectionBannerItem.listFrom([
        {'imageUrl': 'a', 'title': 'Item 1'},
        {'imageUrl': '', 'title': ''}, // nothing to show
        'not a map',
        {'imageUrl': '', 'title': 'No image yet', 'clickActionType': 'Product', 'clickValue': 'p1'},
        {'imageUrl': 'c', 'title': 'C'},
        {'imageUrl': 'd', 'title': 'D'},
        {'imageUrl': 'e', 'title': 'E'},
      ]);
      expect(items.map((e) => e.label), ['', 'No image yet', 'C', 'D']);
      expect(items[1].actionType, 'product');
      expect(items[1].actionValue, 'p1');
      expect(CollectionBannerItem.listFrom(null), isEmpty);
    });
  });

  group('CollectionBannerCard layout', () {
    tearDown(() {
      final binding = TestWidgetsFlutterBinding.instance;
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

    testWidgets('long title: 2 lines max, chevron stays at the right edge',
        (tester) async {
      await _pump(
        tester,
        CollectionBannerCard(
            title: _longTitle, items: _items(4), width: 340),
      );
      expect(tester.takeException(), isNull);

      final card = tester.getRect(find.byType(CollectionBannerCard));
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
      expect(chevron.right, closeTo(card.right - 13, 0.5)); // padding 12 + border 1

      final title = tester.widget<Text>(find.text(_longTitle));
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('height follows content: no empty space below the grid',
        (tester) async {
      await _pump(
        tester,
        CollectionBannerCard(title: 'T', items: _items(4), width: 340),
      );
      final card = tester.getRect(find.byType(CollectionBannerCard));
      final lastLabel = tester.getRect(find.text('Name 4'));
      expect(card.bottom - lastLabel.bottom, closeTo(13, 0.5)); // padding + border
    });

    testWidgets('image cells are square and 4 items make a 2x2 grid',
        (tester) async {
      await _pump(
        tester,
        CollectionBannerCard(title: 'T', items: _items(4), width: 340),
      );
      final cells = find.byType(AspectRatio);
      expect(cells, findsNWidgets(4));
      final r = [for (int i = 0; i < 4; i++) tester.getRect(cells.at(i))];
      for (final c in r) {
        expect(c.width, closeTo(c.height, 0.5));
      }
      expect(r[0].top, r[1].top);
      expect(r[2].top, greaterThan(r[0].bottom));
    });

    testWidgets('3 items sit in one row, no empty cell', (tester) async {
      await _pump(
        tester,
        CollectionBannerCard(title: 'T', items: _items(3), width: 340),
      );
      final cells = find.byType(AspectRatio);
      expect(cells, findsNWidgets(3));
      final tops = {for (int i = 0; i < 3; i++) tester.getRect(cells.at(i)).top};
      expect(tops, hasLength(1));
    });

    testWidgets('1 item shows as a single wide banner', (tester) async {
      await _pump(
        tester,
        CollectionBannerCard(title: 'T', items: _items(1), width: 340),
      );
      final cell = tester.getRect(find.byType(AspectRatio));
      expect(cell.width, closeTo(cell.height * 2, 0.5));
    });

    testWidgets('wide card puts 4 items in one row', (tester) async {
      await _pump(
        tester,
        CollectionBannerCard(
            title: 'T', items: _items(4), width: 1000, isDesktop: true),
        width: 1200,
      );
      final cells = find.byType(AspectRatio);
      final tops = {for (int i = 0; i < 4; i++) tester.getRect(cells.at(i)).top};
      expect(tops, hasLength(1));
    });

    testWidgets('long item names ellipsize; empty names show no label line',
        (tester) async {
      final items = [
        const CollectionBannerItem(
            imageUrl: '',
            label: 'Very very long product name that cannot fit in a cell'),
        const CollectionBannerItem(imageUrl: 'x', label: ''),
        ...CollectionBannerItem.listFrom([
          {'imageUrl': 'y', 'title': 'Item 3'},
          {'imageUrl': 'z', 'title': 'Item 4'},
        ]),
      ];
      await _pump(
        tester,
        CollectionBannerCard(
          title: 'T',
          items: items,
          width: 340,
          imageBuilder: (_, __) => const ColoredBox(color: Colors.blue),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Item '), findsNothing);
      // Only the one named item has a label under its image.
      expect(find.descendant(
          of: find.byType(CollectionBannerCard), matching: find.byType(Text)),
          findsNWidgets(2)); // title + one label
    });

    testWidgets('tapping an item reports that item', (tester) async {
      CollectionBannerItem? tapped;
      final items = _items(4);
      await _pump(
        tester,
        CollectionBannerCard(
            title: 'T', items: items, width: 340, onItemTap: (i) => tapped = i),
      );
      await tester.tap(find.text('Name 3'));
      expect(tapped, same(items[2]));
    });
  });
}
