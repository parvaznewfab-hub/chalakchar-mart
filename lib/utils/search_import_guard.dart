// Client-side mirror of functions/aliexpress/searchImportQueryGuard.js.
// The server enforces the same rules; this copy only stops the app from
// sending requests the server would reject anyway.

const int searchImportMinQueryLength = 3;
const int searchImportMaxQueryLength = 200;

/// search_logs entries are clipped to this length (see firestore.rules).
const int searchLogMaxQueryLength = 100;

final RegExp _urlRe = RegExp(
  r'(https?://|\bwww\.|\b[a-z0-9-]+\.(com|net|org|io|bd|html?|php|aspx?)\b)',
  caseSensitive: false,
);
final RegExp _itemIdRe = RegExp(r'\d{12,}');
final RegExp _codeCharsRe = RegExp(r'[<>{}\[\]`$\\|;=]');
final RegExp _codeWordsRe = RegExp(
  r'\b(https?|www|html?|php|aspx?|javascript|script|onclick|onerror)\b',
  caseSensitive: false,
);
final RegExp _digitsOnlyRe = RegExp(r'^[\d\s.,_-]+$');
final RegExp _hasLetterRe = RegExp(r'\p{L}', unicode: true);

/// Trims and collapses whitespace. Case is preserved.
String normalizeSearchQuery(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Lowercased form used to dedupe a query within one app session.
String searchQueryKey(String raw) => normalizeSearchQuery(raw).toLowerCase();

/// True when [raw] looks like a real product search that may be sent to
/// aliexpressSearchImport.
bool isImportableSearchQuery(String raw) {
  final q = normalizeSearchQuery(raw);
  if (q.length < searchImportMinQueryLength) return false;
  if (q.length > searchImportMaxQueryLength) return false;
  if (_digitsOnlyRe.hasMatch(q)) return false;
  if (_urlRe.hasMatch(q) || _itemIdRe.hasMatch(q)) return false;
  if (_codeCharsRe.hasMatch(q)) return false;
  if (_codeWordsRe.hasMatch(q.replaceAll('_', ' '))) return false;
  if (!_hasLetterRe.hasMatch(q)) return false;
  return true;
}
