import 'package:chalakchar_mart/widgets/identity_document_dialog.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FirebaseFunctionsException err(String code) => FirebaseFunctionsException(code: code, message: 'technical $code');

  test('server refusals become plain Bengali, never the technical text', () {
    for (final code in ['permission-denied', 'unauthenticated', 'not-found', 'failed-precondition', 'unavailable', 'internal']) {
      final shown = identityDocumentErrorText(err(code));
      expect(shown.contains('technical'), isFalse, reason: code);
      expect(shown.contains(code), isFalse, reason: code);
      expect(shown.isNotEmpty, isTrue);
    }
    expect(identityDocumentErrorText(err('permission-denied')), contains('অনুমতি'));
    expect(identityDocumentErrorText(err('not-found')), contains('পাওয়া যায়নি'));
    expect(identityDocumentErrorText(StateError('x')), contains('খোলা যায়নি'));
  });
}
