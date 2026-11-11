import 'category_normalize.dart';

/// Pure helpers over raw `categories` docs, shared by the admin Category
/// Manager and the Product dialog. No Firestore dependency so they can be
/// unit-tested.
///
/// A doc carrying `mergedInto` was folded into another doc by
/// functions/scripts/categoryMerge.js. It is never offered, never reused and
/// never counts as a name clash; references to it are followed to its target.

typedef CategoryDoc = ({String id, Map<String, dynamic> data});

String _text(Object? v) => (v ?? '').toString().trim();

/// The dedup key of a doc, computed from its name (never trusts a stored
/// `normalizedName`, which legacy docs lack and older writes may have stale).
String categoryKeyOf(Map<String, dynamic> data) => normalizeCategoryKey(_text(data['name']));

bool isMergedCategory(Map<String, dynamic> data) => _text(data['mergedInto']).isNotEmpty;

bool isActiveCategory(Map<String, dynamic> data) => data['isActive'] == true;

/// Name of a live (non-merged) category, other than [excludeId], whose key
/// equals [name]'s key; null when [name] is free.
String? findCategoryNameClash(
  Iterable<CategoryDoc> docs,
  String name, {
  String? excludeId,
}) {
  final key = normalizeCategoryKey(name);
  if (key.isEmpty) return null;
  for (final d in docs) {
    if (d.id == excludeId || isMergedCategory(d.data)) continue;
    if (categoryKeyOf(d.data) == key) return _text(d.data['name']);
  }
  return null;
}

/// Follows `mergedInto` from [id] to the live doc. Returns [id] unchanged
/// when it is live, unknown, or the chain loops / dead-ends.
String followMergedCategory(Map<String, Map<String, dynamic>> byId, String id) {
  var current = id;
  final seen = <String>{};
  while (seen.add(current)) {
    final data = byId[current];
    if (data == null) return id;
    final next = _text(data['mergedInto']);
    if (next.isEmpty) return current;
    current = next;
  }
  return id;
}

/// The category doc id a product belongs to.
///
/// [categoryId] wins when it names a known doc (followed through
/// `mergedInto`). Otherwise the product's [categoryName] is matched by
/// normalized key against live docs, preferring active, then ones with a
/// stored `normalizedName` (what the backend resolver would pick), then the
/// lowest id for a stable choice. Null when nothing matches.
String? resolveCategoryId(
  Map<String, Map<String, dynamic>> byId, {
  String? categoryId,
  String? categoryName,
}) {
  final id = _text(categoryId);
  if (id.isNotEmpty && byId.containsKey(id)) {
    final live = followMergedCategory(byId, id);
    if (!isMergedCategory(byId[live]!)) return live;
  }

  final key = normalizeCategoryKey(categoryName);
  if (key.isEmpty) return null;
  final matches = byId.entries
      .where((e) => !isMergedCategory(e.value) && categoryKeyOf(e.value) == key)
      .toList()
    ..sort((a, b) {
      final act = (isActiveCategory(b.value) ? 1 : 0) - (isActiveCategory(a.value) ? 1 : 0);
      if (act != 0) return act;
      final norm = (_text(b.value['normalizedName']).isNotEmpty ? 1 : 0) -
          (_text(a.value['normalizedName']).isNotEmpty ? 1 : 0);
      if (norm != 0) return norm;
      return a.key.compareTo(b.key);
    });
  return matches.isEmpty ? null : matches.first.key;
}
