import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'cloud_functions_urls.dart';

class ImageSearchResult {
  final String productName;
  final String brand;
  final String category;
  final List<String> keywords;
  final String color;
  final String description;

  ImageSearchResult({
    required this.productName,
    required this.brand,
    required this.category,
    required this.keywords,
    required this.color,
    required this.description,
  });

  factory ImageSearchResult.fromJson(Map<String, dynamic> json) {
    return ImageSearchResult(
      productName: (json['productName'] ?? '').toString().trim(),
      brand: (json['brand'] ?? '').toString().trim(),
      category: (json['category'] ?? '').toString().trim(),
      keywords: (json['keywords'] is List)
          ? List<String>.from(
              (json['keywords'] as List).map((e) => e.toString().trim()),
            ).where((e) => e.isNotEmpty).toList()
          : <String>[],
      color: (json['color'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
    );
  }

  /// Best-effort text query to feed into the existing product search/matching logic.
  String get searchQuery {
    final parts = [productName, brand].where((e) => e.trim().isNotEmpty);
    if (parts.isNotEmpty) return parts.join(' ').trim();
    if (keywords.isNotEmpty) return keywords.take(3).join(' ');
    return category;
  }
}

class ImageSearchService {
  static Future<ImageSearchResult?> searchByImage(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final mediaType = _mediaTypeFor(imageFile.name);

      final uri = CloudFunctionsUrls.of('imageProductSearch');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBase64': base64Image,
          'mediaType': mediaType,
        }),
      );

      debugPrint('Image search status: ${response.statusCode}');

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        final errorMessage = data['error'] ??
            'Image search failed with status: ${response.statusCode}';
        throw Exception(errorMessage);
      }

      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        return ImageSearchResult.fromJson(data);
      }

      return null;
    } catch (e, s) {
      debugPrint('Image search error: $e');
      debugPrint('$s');
      rethrow;
    }
  }

  static String _mediaTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
}
