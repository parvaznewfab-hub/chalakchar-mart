import 'package:chalakchar_mart/utils/auth_error_text.dart';
import 'package:flutter_test/flutter_test.dart';

final _bangla = RegExp(r'[ঀ-৿]');

void main() {
  test('every login error is plain Bangla, never raw English', () {
    const codes = [
      'popup-closed-by-user', 'popup-blocked', 'network-request-failed', 'timeout',
      'invalid-phone-number', 'invalid-phone-format', 'invalid-verification-code',
      'session-expired', 'too-many-requests', 'captcha-check-failed',
      'account-exists-with-different-credential', 'credential-already-in-use',
      'user-disabled', 'otp-length', 'unknown', 'internal-error', '',
    ];
    for (final code in codes) {
      final text = authErrorBn(code);
      expect(text, matches(_bangla), reason: code);
      expect(text.contains('Exception'), isFalse, reason: code);
      expect(text.contains(code.isEmpty ? '\u0000' : code), isFalse, reason: code);
    }
  });

  test('specific cases', () {
    expect(authErrorBn('popup-closed-by-user'), contains('বন্ধ'));
    expect(authErrorBn('network-request-failed'), contains('ইন্টারনেট'));
    expect(authErrorBn('invalid-verification-code'), contains('OTP সঠিক নয়'));
    expect(authErrorBn('account-exists-with-different-credential'), startsWith(accountExistsBn));
  });

  test('provider names', () {
    expect(providerNameBn('google.com'), 'Google');
    expect(providerNameBn('facebook.com'), 'Facebook');
    expect(providerNameBn('phone'), 'ফোন OTP');
  });
}
