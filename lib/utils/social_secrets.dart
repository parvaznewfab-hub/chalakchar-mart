// Social media API tokens live in settings/app_secrets (readable only by
// settings editors), not in the public settings/app doc. Same rule as
// functions/settings/socialSecrets.js: a non-empty value in app_secrets wins,
// otherwise a value still left in settings/app (before the move) is used.

const List<String> kSecretSocialApiKeys = [
  'facebookPageAccessToken',
  'instagramAccessToken',
  'whatsappAccessToken',
  'messengerPageAccessToken',
  'tiktokClientSecret',
];

const String kAppSecretsDocId = 'app_secrets';

Map<String, dynamic> socialApiMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

Map<String, dynamic> mergeSocialApiSecrets(
  Map<String, dynamic> publicSocialApi,
  Map<String, dynamic> secretSocialApi,
) {
  final merged = Map<String, dynamic>.from(publicSocialApi);
  for (final key in kSecretSocialApiKeys) {
    final value = secretSocialApi[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      merged[key] = value;
    }
  }
  return merged;
}
