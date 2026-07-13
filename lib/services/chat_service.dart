import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'cloud_functions_urls.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;

  ChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class ChatService {
  static Future<String> sendMessage({
    required String message,
    required List<ChatMessage> history,
  }) async {
    final uri = CloudFunctionsUrls.of('chatWithAssistant');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message.trim(),
        'history': history.map((m) => m.toJson()).toList(),
      }),
    );

    debugPrint('Chat status: ${response.statusCode}');

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      final errorMessage =
          data['error'] ?? 'Chat failed with status: ${response.statusCode}';
      throw Exception(errorMessage);
    }

    final data = jsonDecode(response.body);
    return (data['reply'] ?? '').toString().trim();
  }
}
