import 'package:chalakchar_mart/utils/user_error_message.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final logged = <String>[];
  final original = debugPrint;
  setUp(() {
    logged.clear();
    debugPrint = (String? message, {int? wrapWidth}) => logged.add(message ?? '');
  });
  tearDown(() => debugPrint = original);

  test('permission-denied: plain message, technical text only in the log', () {
    final e = FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Missing or insufficient permissions.');
    final shown = friendlySubmitError(e, where: 'vendor application');
    expect(shown, kSubmitFailedMessage);
    expect(shown.contains('permission'), isFalse);
    expect(shown.contains('cloud_firestore'), isFalse);
    expect(logged.single, contains('[vendor application] failed'));
    expect(logged.single, contains('permission-denied'));
  });

  test('no connection gets its own hint', () {
    final e = FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    expect(friendlySubmitError(e), kNoConnectionMessage);
  });

  test('any other error: the same plain message', () {
    expect(friendlySubmitError(Exception('boom')), kSubmitFailedMessage);
    expect(friendlySubmitError(StateError('x')), kSubmitFailedMessage);
  });
}
