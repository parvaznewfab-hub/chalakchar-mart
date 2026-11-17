import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/category_service.dart';
import '../utils/related_products.dart';
import 'product_card.dart';

/// The product page's related rows: "এই মডেলের আরও পার্টস" (or the series
/// fallback) and "একই ধরনের আরও পণ্য". Rules: utils/related_products.dart.
///
/// Reads at most four small queries (modelKeys / modelSeries / subcategory
/// or category, each with a limit) — never the whole collection. All are
/// single-field filters, so no composite index is needed; visibility is
/// checked on the results.
class RelatedProductsSection extends StatefulWidget {
  const RelatedProductsSection({super.key, required this.product, this.isDesktop = false});

  /// The current product, with its doc id under 'id'.
  final Map<String, dynamic> product;
  final bool isDesktop;

  @override
  State<RelatedProductsSection> createState() => _RelatedProductsSectionState();
}

typedef _Rows = ({ModelRow? model, List<Map<String, dynamic>> similar});

class _RelatedProductsSectionState extends State<RelatedProductsSection> {
  static const int _queryLimit = 40;
  static const int _similarQueryLimit = 60;

  late Future<_Rows> _rows = _load();

  @override
  void initState() {
    super.initState();
    relatedBadProductLogger ??=
        (id, e) => debugPrint('RELATED PRODUCTS ERROR (skipped product $id): $e');
  }

  @override
  void didUpdateWidget(RelatedProductsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product['id'] != widget.product['id']) _rows = _load();
  }

  static List<Map<String, dynamic>> _docs(QuerySnapshot<Map<String, dynamic>> snap) =>
      [for (final d in snap.docs) {...d.data(), 'id': d.id}];

  Future<_Rows> _load() async {
    final watch = Stopwatch()..start();
    final products = FirebaseFirestore.instance.collection('products');
    final current = widget.product;
    final keys = productModelKeys(current);
    final series = productModelSeries(current);
    final subcategoryId = (current['subcategoryId'] ?? '').toString().trim();
    final category = (current['category'] ?? '').toString().trim();

    Future<List<Map<String, dynamic>>> query(Query<Map<String, dynamic>> q) async {
      try {
        return _docs(await q.get());
      } catch (e, st) {
        _log('query', e, st);
        return const [];
      }
    }

    final results = await Future.wait([
      CategoryService.activeCategoryNamesLower()
          .catchError((Object e, StackTrace st) {
        _log('active categories', e, st);
        return <String>{};
      }),
      keys.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : query(products.where('modelKeys', arrayContainsAny: keys.take(30).toList()).limit(_queryLimit)),
      series.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : query(products.where('modelSeries', arrayContainsAny: series.take(30).toList()).limit(_queryLimit)),
      subcategoryId.isNotEmpty
          ? query(products.where('subcategoryId', isEqualTo: subcategoryId).limit(_similarQueryLimit))
          : category.isNotEmpty
              ? query(products.where('category', isEqualTo: category).limit(_similarQueryLimit))
              : Future.value(const <Map<String, dynamic>>[]),
    ]);

    final active = results[0] as Set<String>;
    // Each row on its own: a failure hides that row only, and is logged.
    ModelRow? model;
    try {
      model = pickModelRow(
        current: current,
        exactCandidates: results[1] as List<Map<String, dynamic>>,
        seriesCandidates: results[2] as List<Map<String, dynamic>>,
        activeCategoriesLower: active,
      );
    } catch (e, st) {
      _log('model row', e, st);
    }
    var similar = const <Map<String, dynamic>>[];
    try {
      similar = pickSimilarRow(
        current: current,
        candidates: results[3] as List<Map<String, dynamic>>,
        activeCategoriesLower: active,
        excludeIds: {for (final p in model?.products ?? const []) (p['id'] ?? '').toString()},
      );
    } catch (e, st) {
      _log('similar row', e, st);
    }
    // One line per product page, so a missing row can be told apart from a
    // slow one in the browser console.
    debugPrint('RELATED PRODUCTS: ${model?.products.length ?? 0} model / '
        '${similar.length} similar in ${watch.elapsedMilliseconds} ms');
    return (model: model, similar: similar);
  }

  static void _log(String where, Object error, StackTrace stack) {
    debugPrint('RELATED PRODUCTS ERROR ($where): $error\n$stack');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Rows>(
      future: _rows,
      builder: (context, snap) {
        if (snap.hasError) _log('load', snap.error!, snap.stackTrace ?? StackTrace.empty);
        final rows = snap.data;
        if (rows == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.model != null) _row(context, rows.model!.title, rows.model!.products),
            if (rows.similar.isNotEmpty) _row(context, 'একই ধরনের আরও পণ্য', rows.similar),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, String title, List<Map<String, dynamic>> products) {
    return Container(
      margin: EdgeInsets.only(bottom: widget.isDesktop ? 20 : 12),
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(widget.isDesktop ? 16 : 0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
            ),
          ),
          SizedBox(
            height: ProductCard.rowHeight(context),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: products.length,
              itemBuilder: (context, i) => ProductCard(data: products[i]),
            ),
          ),
        ],
      ),
    );
  }
}

