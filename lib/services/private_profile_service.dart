import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/private_profile_fields.dart';

/// Reads and writes the private halves of vendor and rider profiles
/// (14b step B). Reads merge the private doc over the public one, so old
/// copies left in the public doc keep working until the move script runs.
///
/// A private doc the caller may not read is treated as missing, never as an
/// error: a customer, an admin without the permission, or any user while the
/// live rules do not have vendor_private / delivery_partner_private yet
/// (default deny = permission-denied). The page then shows the public doc.
class PrivateProfileService {
  PrivateProfileService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> vendorPrivateRef(String vendorId) =>
      _db.collection(kVendorPrivateCollection).doc(vendorId);

  static DocumentReference<Map<String, dynamic>> riderPrivateRef(String uid) =>
      _db.collection(kRiderPrivateCollection).doc(uid);

  static Future<Map<String, dynamic>> vendorPrivate(String vendorId) => vendorId.isEmpty
      ? Future.value(<String, dynamic>{})
      : readOrEmpty(() async => (await vendorPrivateRef(vendorId).get()).data());

  static Future<Map<String, dynamic>> riderPrivate(String uid) => uid.isEmpty
      ? Future.value(<String, dynamic>{})
      : readOrEmpty(() async => (await riderPrivateRef(uid).get()).data());

  /// Public vendor data merged with its private doc.
  static Future<Map<String, dynamic>> mergedVendor(String vendorId, Map<String, dynamic>? publicData) async {
    return mergePrivateFields(publicData, await vendorPrivate(vendorId), kVendorPrivateKeys);
  }

  static Future<Map<String, dynamic>> mergedRider(String uid, Map<String, dynamic>? publicData) async {
    return mergePrivateFields(publicData, await riderPrivate(uid), kRiderPrivateKeys);
  }

  /// vendors/{id} and vendor_private/{id} live, merged. Emits null while the
  /// public doc does not exist.
  static Stream<Map<String, dynamic>?> vendorMergedStream(String vendorId) {
    return mergedProfileStream(
      publicDocs: _docData(_db.collection('vendors').doc(vendorId)),
      privateDocs: _docData(vendorPrivateRef(vendorId)),
      privateKeys: kVendorPrivateKeys,
    );
  }

  static Stream<Map<String, dynamic>?> riderMergedStream(String uid) {
    return mergedProfileStream(
      publicDocs: _docData(_db.collection('deliveryPartners').doc(uid)),
      privateDocs: _docData(riderPrivateRef(uid)),
      privateKeys: kRiderPrivateKeys,
    );
  }

  /// null = the doc does not exist.
  static Stream<Map<String, dynamic>?> _docData(DocumentReference<Map<String, dynamic>> ref) =>
      ref.snapshots().map((s) => s.exists ? (s.data() ?? <String, dynamic>{}) : null);

  /// Merge-writes the private keys of [data] into vendor_private/{vendorId}.
  /// Keys that are not private are ignored.
  static Future<void> saveVendorPrivate(String vendorId, Map<String, dynamic> data) async {
    final fields = pickKeys(data, kVendorPrivateKeys);
    if (fields.isEmpty) return;
    await vendorPrivateRef(vendorId).set({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// The private half of a rider application. On a retry (doc already
  /// there from an earlier attempt) createdAt is kept as it was.
  static Future<void> writeRiderApplication(String uid, Map<String, dynamic> fields) async {
    final ref = riderPrivateRef(uid);
    final existing = await readOrEmpty(() async {
      final snap = await ref.get();
      return snap.exists ? {'exists': true} : null;
    });
    await ref.set(riderApplicationPayload(fields, existsAlready: existing.isNotEmpty), SetOptions(merge: true));
  }

  static Future<void> saveRiderPrivate(String uid, Map<String, dynamic> data) async {
    final fields = pickKeys(data, kRiderPrivateKeys);
    if (fields.isEmpty) return;
    await riderPrivateRef(uid).set({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

// ---------------------------------------------------------------------------
// Pure parts (unit-tested in test/private_profile_service_test.dart).
// ---------------------------------------------------------------------------

/// Runs [read]; a missing doc or permission-denied gives {} instead of an
/// error. Other errors (network, etc.) also give {}: the page falls back to
/// the public doc rather than failing.
Future<Map<String, dynamic>> readOrEmpty(Future<Map<String, dynamic>?> Function() read) async {
  try {
    return await read() ?? <String, dynamic>{};
  } on FirebaseException {
    return <String, dynamic>{};
  }
}

/// The rider application's private write: createdAt only on the first
/// attempt, so a retry never changes it.
Map<String, dynamic> riderApplicationPayload(Map<String, dynamic> fields, {required bool existsAlready}) {
  return {
    ...fields,
    if (!existsAlready) 'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Combines a public doc stream and a private doc stream into the merged
/// profile. [publicDocs] emits null while the doc does not exist; errors on
/// [privateDocs] (permission-denied, rules not deployed) count as an empty
/// private doc and never reach the page. Errors on [publicDocs] do.
Stream<Map<String, dynamic>?> mergedProfileStream({
  required Stream<Map<String, dynamic>?> publicDocs,
  required Stream<Map<String, dynamic>?> privateDocs,
  required List<String> privateKeys,
}) {
  late StreamController<Map<String, dynamic>?> controller;
  StreamSubscription<Map<String, dynamic>?>? publicSub;
  StreamSubscription<Map<String, dynamic>?>? privateSub;
  Map<String, dynamic>? publicData;
  var publicSeen = false;
  var privateData = <String, dynamic>{};

  void emit() {
    if (!publicSeen || controller.isClosed) return;
    controller.add(publicData == null ? null : mergePrivateFields(publicData, privateData, privateKeys));
  }

  controller = StreamController<Map<String, dynamic>?>(
    onListen: () {
      publicSub = publicDocs.listen(
        (data) {
          publicSeen = true;
          publicData = data;
          emit();
        },
        onError: controller.addError,
      );
      privateSub = privateDocs.listen(
        (data) {
          privateData = data ?? <String, dynamic>{};
          emit();
        },
        onError: (Object _) {
          privateData = <String, dynamic>{};
          emit();
        },
      );
    },
    onCancel: () async {
      await publicSub?.cancel();
      await privateSub?.cancel();
    },
  );
  return controller.stream;
}
