class AIOptimizedProductModel {
  final String title;
  final String banglaTitle;
  final String description;
  final String banglaDescription;

  final List<String> seoTags;

  final String facebookCaption;
  final String whatsappCaption;

  final String metaTitle;
  final String metaDescription;

  final List<String> searchKeywords;

  final String suggestedCategory;
  final String suggestedSubCategory;
  final String productType;

  AIOptimizedProductModel({
    required this.title,
    required this.banglaTitle,
    required this.description,
    required this.banglaDescription,
    required this.seoTags,
    required this.facebookCaption,
    required this.whatsappCaption,
    required this.metaTitle,
    required this.metaDescription,
    required this.searchKeywords,
    required this.suggestedCategory,
    required this.suggestedSubCategory,
    required this.productType,
  });

  factory AIOptimizedProductModel.fromJson(Map<String, dynamic> json) {
    return AIOptimizedProductModel(
      title: _toText(json['title']),
      banglaTitle: _toText(json['banglaTitle']),
      description: _toText(json['description']),
      banglaDescription: _toText(json['banglaDescription']),
      seoTags: _toStringList(json['seoTags']),
      facebookCaption: _toText(json['facebookCaption']),
      whatsappCaption: _toText(json['whatsappCaption']),
      metaTitle: _toText(json['metaTitle']),
      metaDescription: _toText(json['metaDescription']),
      searchKeywords: _toStringList(json['searchKeywords']),
      suggestedCategory: _toText(json['suggestedCategory']),
      suggestedSubCategory: _toText(json['suggestedSubCategory']),
      productType: _toText(json['productType']),
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
