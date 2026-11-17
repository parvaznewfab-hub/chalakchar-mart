import 'package:chalakchar_mart/utils/social_secrets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secret keys match functions/settings/socialSecrets.js', () {
    expect(kSecretSocialApiKeys.toSet(), {
      'facebookPageAccessToken',
      'instagramAccessToken',
      'whatsappAccessToken',
      'messengerPageAccessToken',
      'tiktokClientSecret',
    });
  });

  test('app_secrets value wins; public ids kept', () {
    final merged = mergeSocialApiSecrets(
      {'facebookPageId': 'p1', 'facebookPageAccessToken': 'old'},
      {'facebookPageAccessToken': 'new'},
    );
    expect(merged['facebookPageAccessToken'], 'new');
    expect(merged['facebookPageId'], 'p1');
  });

  test('before the move the public token is still used', () {
    expect(mergeSocialApiSecrets({'whatsappAccessToken': 'w'}, {})['whatsappAccessToken'], 'w');
  });

  test('empty secret does not wipe; non-secret keys in app_secrets ignored', () {
    final merged = mergeSocialApiSecrets(
      {'whatsappAccessToken': 'w', 'facebookPageId': 'p1'},
      {'whatsappAccessToken': '  ', 'facebookPageId': 'evil'},
    );
    expect(merged['whatsappAccessToken'], 'w');
    expect(merged['facebookPageId'], 'p1');
  });

  test('socialApiMap tolerates non-maps', () {
    expect(socialApiMap(null), isEmpty);
    expect(socialApiMap('x'), isEmpty);
    expect(socialApiMap({'a': 1}), {'a': 1});
  });
}
