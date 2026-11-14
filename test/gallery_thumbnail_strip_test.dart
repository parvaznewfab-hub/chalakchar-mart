import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/widgets/gallery_thumbnail_strip.dart';

// Product page desktop layout: page padding 24*2, card padding 24*2, two
// 28px gaps; the image column is 35% of the rest.
double desktopImageColumn(double screen) => (screen - 48 - 48 - 56) * 0.35;

Widget harness(double width, int count, {int? selected}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: GalleryThumbnailStrip(
              itemCount: count,
              selectedIndex: selected,
              itemBuilder: (_, i, size) => Container(
                key: ValueKey('thumb-$i'),
                color: Colors.blueGrey,
                child: Text('$i'),
              ),
            ),
          ),
        ),
      ),
    );

Rect thumbRect(WidgetTester t, int i) => t.getRect(find.byKey(ValueKey('thumb-$i')));

bool arrowEnabled(WidgetTester t, String key) => t
        .widget<InkWell>(find.descendant(
            of: find.byKey(Key(key)), matching: find.byType(InkWell)))
        .onTap !=
    null;

/// Every thumbnail that shows inside the strip's viewport is shown whole.
void expectWholeThumbnails(WidgetTester t, String when) {
  final strip = t.getRect(find.byKey(const Key('gallery-strip')));
  for (final e in find.byWidgetPredicate((w) => w.key is ValueKey &&
      '${(w.key as ValueKey).value}'.startsWith('thumb-')).evaluate()) {
    final r = t.getRect(find.byWidget(e.widget));
    final overlaps = r.right > strip.left + 0.5 && r.left < strip.right - 0.5;
    if (!overlaps) continue;
    expect(r.left >= strip.left - 0.5 && r.right <= strip.right + 0.5, isTrue,
        reason: '$when: ${(e.widget.key as ValueKey).value} is cut ($r vs strip $strip)');
  }
}

void main() {
  for (final screen in [800.0, 900.0, 1000.0]) {
    testWidgets('6 images at ${screen.toInt()}px: whole thumbnails, arrows, all reachable',
        (t) async {
      await t.pumpWidget(harness(desktopImageColumn(screen), 6));
      await t.pump();
      expect(t.takeException(), isNull);
      expectWholeThumbnails(t, 'at rest');

      // Arrows are in their own columns, outside the thumbnails.
      final strip = t.getRect(find.byKey(const Key('gallery-strip')));
      expect(t.getRect(find.byKey(const Key('gallery-strip-next'))).left,
          greaterThanOrEqualTo(strip.right));
      expect(t.getRect(find.byKey(const Key('gallery-strip-prev'))).right,
          lessThanOrEqualTo(strip.left));
      expect(arrowEnabled(t, 'gallery-strip-next'), isTrue);
      expect(arrowEnabled(t, 'gallery-strip-prev'), isFalse);

      for (var k = 0; k < 6 && arrowEnabled(t, 'gallery-strip-next'); k++) {
        await t.tap(find.byKey(const Key('gallery-strip-next')));
        await t.pumpAndSettle();
        expectWholeThumbnails(t, 'after next #${k + 1}');
      }
      expect(arrowEnabled(t, 'gallery-strip-next'), isFalse);
      expect(arrowEnabled(t, 'gallery-strip-prev'), isTrue);
      expect(thumbRect(t, 5).right, lessThanOrEqualTo(strip.right + 0.5));
    });
  }

  testWidgets('mobile width (347px column) also fits whole thumbnails', (t) async {
    await t.pumpWidget(harness(347, 6));
    await t.pump();
    expectWholeThumbnails(t, 'mobile');
  });

  testWidgets('mouse drag scrolls the strip (desktop web)', (t) async {
    await t.pumpWidget(harness(desktopImageColumn(900), 6));
    await t.pump();
    double offset() => t.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(offset(), 0);
    final gesture = await t.startGesture(t.getCenter(find.byKey(const ValueKey('thumb-1'))),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(-120, 0));
    await gesture.up();
    await t.pumpAndSettle();
    expect(offset(), greaterThan(50));
  });

  testWidgets('changing the selection scrolls it into view', (t) async {
    final width = desktopImageColumn(800);
    await t.pumpWidget(harness(width, 6, selected: 0));
    await t.pump();
    await t.pumpWidget(harness(width, 6, selected: 5));
    await t.pumpAndSettle();
    final strip = t.getRect(find.byKey(const Key('gallery-strip')));
    expect(thumbRect(t, 5).right, lessThanOrEqualTo(strip.right + 0.5));
  });

  testWidgets('few images: all fit, no arrows', (t) async {
    await t.pumpWidget(harness(desktopImageColumn(1440), 3));
    await t.pump();
    expect(find.byKey(const Key('gallery-strip-next')), findsNothing);
    expect(find.byKey(const Key('gallery-strip-prev')), findsNothing);
    expect(t.getSize(find.byKey(const ValueKey('thumb-0'))).width, 86);
  });
}
