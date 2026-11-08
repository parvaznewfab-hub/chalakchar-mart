import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_functions_urls.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;

  ChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class ChatService {
  static const String _guestIdPrefsKey = 'chat_guest_id';

  // Persisted across app restarts so the same signed-out visitor keeps the
  // same conversations/{conversationId} thread server-side (see the
  // omnichannel messaging pipeline spec's conversation-id convention),
  // instead of starting a brand-new thread on every cold start.
  static Future<String> _getOrCreateGuestId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_guestIdPrefsKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generateGuestId();
    await prefs.setString(_guestIdPrefsKey, generated);
    return generated;
  }

  static String _generateGuestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<String> sendMessage({required String message}) async {
    final uri = CloudFunctionsUrls.of('chatWithAssistant');

    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    final guestId = await _getOrCreateGuestId();

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'message': message.trim(),
        'guestId': guestId,
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
