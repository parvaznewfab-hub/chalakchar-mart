// 14b step B: which vendor / rider fields are private.
//
// Private values live in vendor_private/{vendorId} and
// delivery_partner_private/{uid}; the public vendors/{id} and
// deliveryPartners/{uid} docs must not get new private values (firestore.rules
// noNewVendorPrivateKeys / noNewRiderPrivateKeys). Keep these lists equal to
// those rules and to functions/scripts/movePrivateProfiles.js.
//
// Until the move script has run, an old copy may still sit in the public doc,
// so readers merge both: a non-empty private value wins, otherwise the old
// public value is used.

/// Contact, documents and payout account: the vendor owner may edit these.
const List<String> kVendorPrivateProfileKeys = [
  'phone',
  'email',
  'address',
  'ownerName',
  'note',
  // Old download links (token URLs). Never written again by the app: new
  // documents are stored as Storage paths below (14b step B / C).
  'nidFront',
  'nidBack',
  'tradeLicense',
  'nidFrontPath',
  'nidBackPath',
  'tradeLicensePath',
  'payoutAccount',
  'payoutNumber',
];

/// Commission and balances: vendor managers / payout staff only.
const List<String> kVendorPrivateMoneyKeys = [
  'commissionPercent',
  'commissionRate',
  'totalSales',
  'totalCommission',
  'pendingBalance',
  'withdrawableBalance',
  'withdrawPendingBalance',
  'totalPaidOut',
  'deliveredOrders',
  'cancelledOrders',
];

const List<String> kVendorPrivateKeys = [
  ...kVendorPrivateProfileKeys,
  ...kVendorPrivateMoneyKeys,
];

/// NID, address, email of a rider. Name and phone stay public (the phone is
/// copied into orders for the customer); money totals stay in
/// deliveryPartners until the rider sync moves to a function.
const List<String> kRiderPrivateKeys = [
  'nidNumber',
  'nidFrontUrl',
  'nidBackUrl',
  'nidFrontPath',
  'nidBackPath',
  'address',
  'email',
  'note',
];

const String kVendorPrivateCollection = 'vendor_private';
const String kRiderPrivateCollection = 'delivery_partner_private';

bool _hasValue(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  return true;
}

/// Public doc + private doc. For each private key a non-empty private value
/// wins, otherwise a value left in the public doc (before the move) is used.
Map<String, dynamic> mergePrivateFields(
  Map<String, dynamic>? publicData,
  Map<String, dynamic>? privateData,
  List<String> privateKeys,
) {
  final merged = <String, dynamic>{...?publicData};
  final private = privateData ?? const <String, dynamic>{};
  for (final key in privateKeys) {
    if (_hasValue(private[key])) merged[key] = private[key];
  }
  return merged;
}

/// Only the private keys of [data] (for writing to the private doc).
Map<String, dynamic> pickKeys(Map<String, dynamic> data, List<String> keys) {
  return {
    for (final key in keys)
      if (data.containsKey(key)) key: data[key],
  };
}

/// [data] without any private key (for writing to the public doc).
Map<String, dynamic> withoutKeys(Map<String, dynamic> data, List<String> keys) {
  return {
    for (final entry in data.entries)
      if (!keys.contains(entry.key)) entry.key: entry.value,
  };
}

/// The Storage object path inside a Firebase download URL
/// (".../o/vendors%2Fabc%2Fdocuments%2Fnid.jpeg?alt=media&token=..."), or ''
/// when [value] is not such a URL. A value that already is a path (no
/// scheme) is returned as is. Never returns the token.
String storagePathFromUrlOrPath(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return '';
  if (!text.startsWith('http://') && !text.startsWith('https://')) return text;
  final uri = Uri.tryParse(text);
  if (uri == null) return '';
  final segments = uri.pathSegments;
  final i = segments.indexOf('o');
  if (i < 0 || i + 1 >= segments.length) return '';
  // pathSegments are already percent-decoded.
  return segments.sublist(i + 1).join('/');
}

/// Document path for a vendor document, preferring the new *Path field and
/// falling back to the path inside an old download link.
String vendorDocumentPath(Map<String, dynamic>? data, String kind) {
  final d = data ?? const <String, dynamic>{};
  final path = (d['${kind}Path'] ?? '').toString().trim();
  if (path.isNotEmpty) return path;
  return storagePathFromUrlOrPath(d[kind]?.toString());
}
