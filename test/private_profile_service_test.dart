import 'dart:async';

import 'package:chalakchar_mart/services/private_profile_service.dart';
import 'package:chalakchar_mart/utils/private_profile_fields.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Missing or insufficient permissions.');

void main() {
  group('readOrEmpty (private doc reads)', () {
    test('permission-denied -> {} (no error shown, page falls back to the public doc)', () async {
      expect(await readOrEmpty(() async => throw _denied()), isEmpty);
    });
    test('missing doc -> {}', () async {
      expect(await readOrEmpty(() async => null), isEmpty);
    });
    test('readable doc -> its data', () async {
      expect(await readOrEmpty(() async => {'phone': '017'}), {'phone': '017'});
    });
  });

  group('mergedProfileStream', () {
    test('private stream fails with permission-denied: public doc still shown, no error', () async {
      final pub = StreamController<Map<String, dynamic>?>();
      final priv = StreamController<Map<String, dynamic>?>();
      final errors = <Object>[];
      final values = <Map<String, dynamic>?>[];
      final sub = mergedProfileStream(publicDocs: pub.stream, privateDocs: priv.stream, privateKeys: kVendorPrivateKeys)
          .listen(values.add, onError: errors.add);

      priv.addError(_denied());
      pub.add({'shopName': 'S', 'phone': 'old copy'});
      await Future<void>.delayed(Duration.zero);

      expect(errors, isEmpty);
      expect(values.last, {'shopName': 'S', 'phone': 'old copy'});
      await sub.cancel();
    });

    test('private doc arrives later and wins over the old public copy', () async {
      final pub = StreamController<Map<String, dynamic>?>();
      final priv = StreamController<Map<String, dynamic>?>();
      final values = <Map<String, dynamic>?>[];
      final sub = mergedProfileStream(publicDocs: pub.stream, privateDocs: priv.stream, privateKeys: kVendorPrivateKeys)
          .listen(values.add);

      pub.add({'shopName': 'S', 'phone': 'old'});
      await Future<void>.delayed(Duration.zero);
      priv.add({'phone': 'new', 'withdrawableBalance': 50});
      await Future<void>.delayed(Duration.zero);

      expect(values.last, {'shopName': 'S', 'phone': 'new', 'withdrawableBalance': 50});
      await sub.cancel();
    });

    test('public doc missing -> null; nothing before the public doc arrives', () async {
      final pub = StreamController<Map<String, dynamic>?>();
      final priv = StreamController<Map<String, dynamic>?>();
      final values = <Map<String, dynamic>?>[];
      final sub = mergedProfileStream(publicDocs: pub.stream, privateDocs: priv.stream, privateKeys: kRiderPrivateKeys)
          .listen(values.add);

      priv.add({'nidNumber': '1'});
      await Future<void>.delayed(Duration.zero);
      expect(values, isEmpty);
      pub.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(values, [null]);
      await sub.cancel();
    });

    test('an error on the PUBLIC doc does reach the page', () async {
      final pub = StreamController<Map<String, dynamic>?>();
      final priv = StreamController<Map<String, dynamic>?>();
      final errors = <Object>[];
      final sub = mergedProfileStream(publicDocs: pub.stream, privateDocs: priv.stream, privateKeys: kVendorPrivateKeys)
          .listen((_) {}, onError: errors.add);
      pub.addError(_denied());
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      await sub.cancel();
    });
  });

  group('riderApplicationPayload (retry)', () {
    test('first attempt sets createdAt; a retry keeps the old one', () {
      final first = riderApplicationPayload({'nidNumber': '1'}, existsAlready: false);
      final retry = riderApplicationPayload({'nidNumber': '1'}, existsAlready: true);
      expect(first.containsKey('createdAt'), isTrue);
      expect(retry.containsKey('createdAt'), isFalse);
      expect(retry['updatedAt'], isA<FieldValue>());
      expect(retry['nidNumber'], '1');
    });
  });

  group('vendorCommissionPercent', () {
    test('never set -> 10% default', () {
      expect(vendorCommissionPercent(null), 10);
      expect(vendorCommissionPercent({}), 10);
      expect(vendorCommissionPercent({'commissionPercent': null}), 10);
      expect(vendorCommissionPercent({'commissionPercent': '  '}), 10);
    });
    test('admin set 0% -> stays 0%', () {
      expect(vendorCommissionPercent({'commissionPercent': 0}), 0);
      expect(vendorCommissionPercent({'commissionPercent': '0'}), 0);
      expect(vendorCommissionPercent({'commissionPercent': 0, 'commissionRate': 10}), 0);
    });
    test('admin set value wins; older commissionRate used when commissionPercent is missing', () {
      expect(vendorCommissionPercent({'commissionPercent': 7.5}), 7.5);
      expect(vendorCommissionPercent({'commissionRate': 12}), 12);
    });
  });
}
