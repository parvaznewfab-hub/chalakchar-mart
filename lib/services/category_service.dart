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