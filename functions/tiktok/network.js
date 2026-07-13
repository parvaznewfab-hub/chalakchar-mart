const dns = require("dns");
const net = require("net");
const axios = require("axios");

class SsrfBlockedError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "SsrfBlockedError";
    this.code = code;
  }
}

// base IP, prefix length — every RFC1918/link-local/loopback/CGNAT/
// documentation/multicast/reserved/broadcast range, including the cloud
// metadata address 169.254.169.254 (covered by 169.254.0.0/16).
const BLOCKED_IPV4_RANGES = [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["100.64.0.0", 10],
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.0.2.0", 24],
  ["192.168.0.0", 16],
  ["198.18.0.0", 15],
  ["198.51.100.0", 24],
  ["203.0.113.0", 24],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
  ["255.255.255.255", 32],
];

// Prefix-based matching for IPv6 — covers ::1 (loopback), :: (unspecified),
// fc00::/7 (unique local, includes AWS's fd00:ec2::254 metadata address),
// fe80::/10 (link-local), ff00::/8 (multicast), 2001:db8::/32
// (documentation), 64:ff9b:: (NAT64 — embedded IPv4 checked separately).
const BLOCKED_IPV6_PREFIXES = ["fc", "fd", "fe8", "fe9", "fea", "feb", "ff", "2001:db8", "64:ff9b:"];

function ipv4ToInt(ip) {
  return ip.split(".").reduce((acc, part) => (acc << 8) + Number(part), 0) >>> 0;
}

function isBlockedIpv4(ip) {
  const target = ipv4ToInt(ip);
  return BLOCKED_IPV4_RANGES.some(([base, bits]) => {
    const mask = bits === 0 ? 0 : (~0 << (32 - bits)) >>> 0;
    return (target & mask) === (ipv4ToInt(base) & mask);
  });
}

function isBlockedIpv6(ip) {
  const normalized = ip.toLowerCase();
  if (normalized === "::1" || normalized === "::") return true;
  if (BLOCKED_IPV6_PREFIXES.some((prefix) => normalized.startsWith(prefix))) return true;

  const mapped = normalized.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return isBlockedIpv4(mapped[1]);

  return false;
}

function isDisallowedIp(ip) {
  const family = net.isIP(ip);
  if (family === 4) return isBlockedIpv4(ip);
  if (family === 6) return isBlockedIpv6(ip);
  return true; // couldn't classify — fail closed
}

function isIpLiteralHostname(hostname) {
  return net.isIP(hostname) !== 0;
}

// Resolves the hostname, rejects if it is (or resolves to) a private/
// reserved/metadata address, and returns ONE validated address to pin the
// actual connection to — this is what prevents DNS rebinding: a second,
// different DNS answer at connect time is never consulted, because we never
// let axios re-resolve the hostname itself (see safeHead's `lookup` option).
async function resolveAndValidateHost(hostname) {
  if (isIpLiteralHostname(hostname)) {
    throw new SsrfBlockedError("IP_LITERAL_HOST", "Raw IP addresses are not allowed as media hosts.");
  }

  let addresses;
  try {
    addresses = await dns.promises.lookup(hostname, { all: true, verbatim: true });
  } catch (_error) {
    throw new SsrfBlockedError("DNS_RESOLUTION_FAILED", `Could not resolve host "${hostname}".`);
  }

  if (!addresses.length) {
    throw new SsrfBlockedError("DNS_RESOLUTION_FAILED", `Host "${hostname}" resolved to no addresses.`);
  }

  for (const { address } of addresses) {
    if (isDisallowedIp(address)) {
      throw new SsrfBlockedError("PRIVATE_OR_RESERVED_IP", `Host "${hostname}" resolves to a disallowed address.`);
    }
  }

  return addresses[0];
}

// A HEAD request with SSRF protections applied:
//  - hostname pre-resolved and validated (no private/reserved/metadata IPs)
//  - connection pinned to the validated address (DNS-rebinding resistant)
//  - redirects disabled outright, never followed
//  - no credentials, no cookies, minimal headers
//  - strict timeout, zero response body permitted (this is a HEAD request)
async function safeHead(url) {
  const parsed = new URL(url);

  if (parsed.username || parsed.password) {
    throw new SsrfBlockedError("URL_CREDENTIALS_NOT_ALLOWED", "URLs with embedded credentials are not allowed.");
  }

  const validatedAddress = await resolveAndValidateHost(parsed.hostname);

  const pinnedLookup = (_hostname, _options, callback) => {
    callback(null, validatedAddress.address, validatedAddress.family);
  };

  try {
    return await axios.head(url, {
      timeout: 8000,
      maxRedirects: 0,
      maxContentLength: 0,
      maxBodyLength: 0,
      lookup: pinnedLookup,
      validateStatus: (status) => status >= 200 && status < 300,
      withCredentials: false,
      headers: { Accept: "*/*" }, // no Authorization, no Cookie — nothing forwarded
    });
  } catch (error) {
    if (error.response && error.response.status >= 300 && error.response.status < 400) {
      throw new SsrfBlockedError("REDIRECT_NOT_ALLOWED", "The media URL responded with a redirect, which is not permitted.");
    }
    throw error;
  }
}

module.exports = {
  safeHead,
  resolveAndValidateHost,
  isDisallowedIp,
  isIpLiteralHostname,
  isBlockedIpv4,
  isBlockedIpv6,
  SsrfBlockedError,
};
