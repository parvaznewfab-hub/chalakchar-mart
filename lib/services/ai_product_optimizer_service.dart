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
}