class AIOptimizedProductModel {
  final String title;
  final String banglaTitle;
  final String description;
  final List<String> seoTags;

  AIOptimizedProductModel({
    required this.title,
    required this.banglaTitle,
    required this.description,
    required this.seoTags,
  });

  factory AIOptimizedProductModel.fromJson(Map<String, dynamic> json) {
    return AIOptimizedProductModel(
      title: _toText(json['title']),
      banglaTitle: _toText(json['banglaTitle']),
      description: _toText(json['description']),
      seoTags: _toStringList(json['seoTags']),
    );
  }

  static String _toText(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  static List<String> _toStringList(dynamic value) {
    if (value == null) return [];

    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    if (value is String) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return [];
  }
}