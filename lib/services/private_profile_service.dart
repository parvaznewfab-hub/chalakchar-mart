import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/private_profile_fields.dart';

/// Reads and writes the private halves of vendor and rider profiles
/// (14b step B). Reads merge the private doc over the public one, so old
/// copies left in the public doc keep working until the move script runs.
/// A private doc the caller may not read (a customer, or before the rules
/// are deployed) is treated as empty.
class PrivateProfileService {
  PrivateProfileService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> vendorPrivateRef(String vendorId) =>
      _db.collection(kVendorPrivateCollection).doc(vendorId);

  static DocumentReference<Map<String, dynamic>> riderPrivateRef(String uid) =>
      _db.collection(kRiderPrivateCollection).doc(uid);

  static Future<Map<String, dynamic>> _readOrEmpty(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return (await ref.get()).data() ?? <String, dynamic>{};
    } on FirebaseException {
      return <String, dynamic>{};
    }
  }

  static Future<Map<String, dynamic>> vendorPrivate(String vendorId) =>
      vendorId.isEmpty ? Future.value(<String, dynamic>{}) : _readOrEmpty(vendorPrivateRef(vendorId));

  static Future<Map<String, dynamic>> riderPrivate(String uid) =>
      uid.isEmpty ? Future.value(<String, dynamic>{}) : _readOrEmpty(riderPrivateRef(uid));

  /// Public vendor data merged with its private doc.
  static Future<Map<String, dynamic>> mergedVendor(String vendorId, Map<String, dynamic>? publicData) async {
    return mergePrivateFields(publicData, await vendorPrivate(vendorId), kVendorPrivateKeys);
  }

  static Future<Map<String, dynamic>> mergedRider(String uid, Map<String, dynamic>? publicData) async {
    return mergePrivateFields(publicData, await riderPrivate(uid), kRiderPrivateKeys);
  }

  /// vendors/{id} and vendor_private/{id} live, merged. Emits null while the
  /// public doc does not exist. Private read errors count as an empty doc.
  static Stream<Map<String, dynamic>?> vendorMergedStream(String vendorId) {
    return _mergedStream(
      _db.collection('vendors').doc(vendorId),
      vendorPrivateRef(vendorId),
      kVendorPrivateKeys,
    );
  }

  static Stream<Map<String, dynamic>?> riderMergedStream(String uid) {
    return _mergedStream(
      _db.collection('deliveryPartners').doc(uid),
      riderPrivateRef(uid),
      kRiderPrivateKeys,
    );
  }

  static Stream<Map<String, dynamic>?> _mergedStream(
    DocumentReference<Map<String, dynamic>> publicRef,
    DocumentReference<Map<String, dynamic>> privateRef,
    List<String> keys,
  ) {
    late StreamController<Map<String, dynamic>?> controller;
    StreamSubscription? publicSub;
    StreamSubscription? privateSub;
    Map<String, dynamic>? publicData;
    var publicExists = false;
    var publicSeen = false;
    var privateData = <String, dynamic>{};

    void emit() {
      if (!publicSeen || controller.isClosed) return;
      controller.add(publicExists ? mergePrivateFields(publicData, privateData, keys) : null);
    }

    controller = StreamController<Map<String, dynamic>?>(
      onListen: () {
        publicSub = publicRef.snapshots().listen(
          (snap) {
            publicSeen = true;
            publicExists = snap.exists;
            publicData = snap.data();
            emit();
          },
          onError: controller.addError,
        );
        privateSub = privateRef.snapshots().listen(
          (snap) {
            privateData = snap.data() ?? <String, dynamic>{};
            emit();
          },
          // No permission (customer) or rules not deployed yet: stay empty.
          onError: (_) {},
        );
      },
      onCancel: () async {
        await publicSub?.cancel();
        await privateSub?.cancel();
      },
    );
    return controller.stream;
  }

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

  static Future<void> saveRiderPrivate(String uid, Map<String, dynamic> data) async {
    final fields = pickKeys(data, kRiderPrivateKeys);
    if (fields.isEmpty) return;
    await riderPrivateRef(uid).set({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
