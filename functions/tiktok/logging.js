const SENSITIVE_KEYS = new Set([
  "authorization",
  "access_token",
  "accessToken",
  "refresh_token",
  "refreshToken",
  "client_secret",
  "clientSecret",
  "code",
  "state",
  "password",
]);

function scrub(value, depth) {
  if (depth > 4 || value === null || value === undefined) return value;
  if (Array.isArray(value)) return value.map((entry) => scrub(entry, depth + 1));

  if (typeof value === "object") {
    const out = {};
    for (const [key, val] of Object.entries(value)) {
      out[key] = SENSITIVE_KEYS.has(key) ? "[redacted]" : scrub(val, depth + 1);
    }
    return out;
  }

  return value;
}

// Never pass a raw axios error or OAuth response straight to logger.error() —
// always route it through this first. axios errors embed the full request
// config (including Authorization headers) by default.
function redactSecrets(input) {
  if (input instanceof Error) {
    const responseData = input.response && input.response.data ? scrub(input.response.data, 0) : undefined;
    return {
      message: input.message,
      name: input.name,
      responseData,
      requestUrl: input.config ? input.config.url : undefined,
      requestMethod: input.config ? input.config.method : undefined,
    };
  }

  return scrub(input, 0);
}

module.exports = { redactSecrets };
