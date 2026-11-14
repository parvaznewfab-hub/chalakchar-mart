import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryService {
  CategoryService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _ref =>
      _db.collection('categories');

  static Stream<List<CategoryModel>> watchActiveCategories() {
    return _ref.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => CategoryModel.fromDoc(doc.id, doc.data()))
          .where((cat) => cat.isActive)
          .toList();

      list.sort((a, b) => a.priority.compareTo(b.priority));
      return list;
    });
  }

  static Stream<List<CategoryModel>> watchHomeCategories() {
    return _ref.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => CategoryModel.fromDoc(doc.id, doc.data()))
          .where((cat) => cat.isActive && cat.showOnHome)
          .toList();

      list.sort((a, b) => a.priority.compareTo(b.priority));
      return list;
    });
  }

  static Future<List<CategoryModel>> getActiveCategoriesOnce() async {
    final snapshot = await _ref.get();

    final list = snapshot.docs
        .map((doc) => CategoryModel.fromDoc(doc.id, doc.data()))
        .where((cat) => cat.isActive)
        .toList();

    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  /// URL slug for a category name — the same rule the /category/{slug}
  /// route and the home page have always used.
  static String slugOf(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  static Future<Map<String, List<SubcategoryModel>>>? _subcategoryCache;

  /// Active subcategories grouped by parent categoryId, each list sorted by
  /// priority then name. Read once per app session and cached, so the
  /// sidebar and category page never re-read `subcategories`. A failed
  /// read is not cached, so the next caller retries.
  static Future<Map<String, List<SubcategoryModel>>> activeSubcategoriesByCategory() {
    return _subcategoryCache ??= _loadSubcategories().catchError((Object e) {
      _subcategoryCache = null;
      throw e;
    });
  }

  static Future<Map<String, int>>? _liveCountCache;

  /// Live product count (isActive + approved, as customers see them) per
  /// active subcategory id. One count() aggregation per subcategory, once
  /// per app session; a failed load is not cached.
  static Future<Map<String, int>> liveProductCountsBySubcategory() {
    return _liveCountCache ??= _loadLiveCounts().catchError((Object e) {
      _liveCountCache = null;
      throw e;
    });
  }

  static Future<Map<String, int>> _loadLiveCounts() async {
    final grouped = await activeSubcategoriesByCategory();
    final subs = grouped.values.expand((list) => list).toList();
    final counts = await Future.wait(subs.map((sub) async {
      final agg = await _db
          .collection('products')
          .where('subcategoryId', isEqualTo: sub.id)
          .where('isActive', isEqualTo: true)
          .where('approvalStatus', isEqualTo: 'approved')
          .count()
          .get();
      return MapEntry(sub.id, agg.count ?? 0);
    }));
    return Map.fromEntries(counts);
  }

  static Future<Map<String, List<SubcategoryModel>>> _loadSubcategories() async {
    final snapshot = await _db.collection('subcategories').get();
    final grouped = <String, List<SubcategoryModel>>{};
    for (final doc in snapshot.docs) {
      final sub = SubcategoryModel.fromDoc(doc.id, doc.data());
      if (!sub.isActive || sub.categoryId.isEmpty) continue;
      grouped.putIfAbsent(sub.categoryId, () => []).add(sub);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        final byPriority = a.priority.compareTo(b.priority);
        if (byPriority != 0) return byPriority;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    return grouped;
  }
}

class SubcategoryModel {
  final String id;
  final String categoryId;
  final String name;
  final String slug;
  final String imageUrl;
  final int priority;
  final bool isActive;

  const SubcategoryModel({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.slug,
    required this.imageUrl,
    required this.priority,
    required this.isActive,
  });

  factory SubcategoryModel.fromDoc(String id, Map<String, dynamic> data) {
    String text(dynamic value) => (value ?? '').toString().trim();
    final priority = data['priority'];
    final name = text(data['name']);
    final slug = text(data['slug']);
    return SubcategoryModel(
      id: id,
      categoryId: text(data['categoryId']),
      name: name,
      slug: slug.isEmpty ? CategoryService.slugOf(name) : slug,
      imageUrl: text(data['imageUrl'] ?? data['image']),
      priority: priority is num ? priority.toInt() : int.tryParse(text(priority)) ?? 0,
      // Merged/retired subcategories (mergedInto set) are never shown.
      isActive: data['isActive'] == true && text(data['mergedInto']).isEmpty,
    );
  }
}

class CategoryModel {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final int priority;
  final bool isActive;
  final bool isFeatured;
  final bool showOnHome;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.priority,
    required this.isActive,
    required this.isFeatured,
    required this.showOnHome,
  });

  factory CategoryModel.fromDoc(String id, Map<String, dynamic> data) {
    String text(dynamic value, [String fallback = '']) {
      final t = (value ?? '').toString().trim();
      return t.isEmpty ? fallback : t;
    }

    int intValue(dynamic value, [int fallback = 0]) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return CategoryModel(
      id: id,
      name: text(data['name']),
      description: text(data['description']),
      imageUrl: text(data['imageUrl'] ?? data['image']),
      priority: intValue(data['priority']),
      isActive: data['isActive'] == true,
      isFeatured: data['isFeatured'] == true,
      showOnHome: data['showOnHome'] != false,
    );
  }
}