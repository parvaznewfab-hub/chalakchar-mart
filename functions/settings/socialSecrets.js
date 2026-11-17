// Social media API tokens live in settings/app_secrets (readable only by
// settings editors), not in the public settings/app doc.
//
// settings/app.socialApi keeps the non-secret parts (page id, Instagram
// business id, WhatsApp phone number id, TikTok client key, flags...).
// settings/app_secrets.socialApi holds only the keys below.
//
// Until the move script has run, the tokens may still be in settings/app, so
// readers merge both: a non-empty value in app_secrets wins, otherwise the old
// settings/app value is used.

const SECRET_SOCIAL_API_KEYS = Object.freeze([
  "facebookPageAccessToken",
  "instagramAccessToken",
  "whatsappAccessToken",
  "messengerPageAccessToken",
  "tiktokClientSecret",
]);

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasText(value) {
  return value !== null && value !== undefined && String(value).trim().length > 0;
}

function mergeSocialApiSecrets(publicSocialApi, secretSocialApi) {
  const merged = isPlainObject(publicSocialApi) ? { ...publicSocialApi } : {};
  const secrets = isPlainObject(secretSocialApi) ? secretSocialApi : {};
  for (const key of SECRET_SOCIAL_API_KEYS) {
    if (hasText(secrets[key])) merged[key] = secrets[key];
  }
  return merged;
}

// For the move script: which secret keys settings/app still holds, and the
// values to copy. Never logs or returns anything but the copy itself.
function secretsInPublicSocialApi(publicSocialApi) {
  const api = isPlainObject(publicSocialApi) ? publicSocialApi : {};
  const present = SECRET_SOCIAL_API_KEYS.filter((key) => Object.prototype.hasOwnProperty.call(api, key));
  const toCopy = {};
  for (const key of present) {
    if (hasText(api[key])) toCopy[key] = api[key];
  }
  return { present, toCopy };
}

module.exports = { SECRET_SOCIAL_API_KEYS, mergeSocialApiSecrets, secretsInPublicSocialApi };
