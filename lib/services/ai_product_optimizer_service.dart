import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_optimized_product_model.dart';

class AIProductOptimizerService {
  static Future<AIOptimizedProductModel?> optimize({
    required String title,
    required String description,
    required String category,
  }) async {
    try {
      final uri = Uri.parse(
        'https://aioptimizeproduct-n2eumsvxdq-el.a.run.app',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title.trim(),
          'description': description.trim(),
          'category': category.trim(),
        }),
      );

      debugPrint('AI Optimize status: ${response.statusCode}');
      debugPrint('AI Optimize body: ${response.body}');

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        final errorMessage = data['error'] ?? 'Optimization failed with status: ${response.statusCode}';
        throw Exception(errorMessage);
      }

      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic>) {
        return AIOptimizedProductModel.fromJson(data);
      }

      return null;
    } catch (e, s) {
      debugPrint('AI optimize error: $e');
      debugPrint('$s');
      rethrow; // Rethrow to let the UI handle it
    }
  }

  static Future<String?> generateProductImage({
    required String imageUrl,
    required String productName,
    required String style,
    String customPrompt = '',
  }) async {
    try {
      final uri = Uri.parse(
        'https://asia-south1-chalakchar-mart.cloudfunctions.net/aiGenerateProductImage',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageUrl': imageUrl.trim(),
          'productName': productName.trim(),
          'style': style.trim(),
          'customPrompt': customPrompt.trim(),
        }),
      );

      debugPrint('AI Generate Product Image status: ${response.statusCode}');
      debugPrint('AI Generate Product Image body: ${response.body}');

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        final errorMessage = data['error'] ??
            'AI image generation failed with status: ${response.statusCode}';
        throw Exception(errorMessage);
      }

      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic>) {
        final generatedUrl = (data['imageUrl'] ?? '').toString().trim();
        return generatedUrl.isEmpty ? null : generatedUrl;
      }

      return null;
    } catch (e, s) {
      debugPrint('AI product image generation error: $e');
      debugPrint('$s');
      rethrow;
    }
  }

  static Future<AIOptimizedProductModel?> optimizeFromImage({
    required String imageUrl,
    String hintTitle = '',
    String hintCategory = '',
  }) async {
    try {
      final uri = Uri.parse(
        'https://asia-south1-chalakchar-mart.cloudfunctions.net/aiProductFromImage',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageUrl': imageUrl.trim(),
          'hintTitle': hintTitle.trim(),
          'hintCategory': hintCategory.trim(),
        }),
      );

      debugPrint('AI Image Product status: ${response.statusCode}');
      debugPrint('AI Image Product body: ${response.body}');

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        final errorMessage = data['error'] ??
            'Image AI failed with status: ${response.statusCode}';
        throw Exception(errorMessage);
      }

      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic>) {
        return AIOptimizedProductModel.fromJson(data);
      }

      return null;
    } catch (e, s) {
      debugPrint('AI image product error: $e');
      debugPrint('$s');
      rethrow;
    }
  }
}
