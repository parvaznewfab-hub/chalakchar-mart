// When a settled search (Enter, opened with a query, or typing stopped) may
// be logged and, on a miss, start an AliExpress search import.
//
// Firestore first answers a listener from its local cache: only the products
// other screens happened to read (the home grid, the header suggestions), so
// a word that matches hidden grocery items looks like a miss there. The
// decision therefore waits for a list confirmed by the server, and a failed
// server read (no network, rules) decides nothing.

import 'search_import_guard.dart';

class SettledSearchGate {
  String? _pending;

  /// The settled query still waiting for a server list.
  String? get pending => _pending;

  void settle(String query) {
    if (query.trim().isNotEmpty) _pending = query;
  }

  void clear() => _pending = null;

  /// A product list arrived. Returns the settled query to decide on now, or
  /// null: nothing settled, the list is only from the local cache (keep
  /// waiting), the read failed (dropped), or the shopper has typed something
  /// else since (dropped).
  String? take({
    required String currentQuery,
    required bool fromCache,
    required bool failed,
  }) {
    final query = _pending;
    if (query == null) return null;
    if (failed) {
      _pending = null;
      return null;
    }
    if (fromCache) return null;
    _pending = null;
    return query == currentQuery ? query : null;
  }
}

/// A settled search starts an import only when the server's list has no
/// match at all and the words are worth looking up.
bool shouldImportSearch(String query, int matchCount) =>
    matchCount == 0 && isImportableSearchQuery(query);
