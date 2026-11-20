import 'package:chalakchar_mart/utils/private_profile_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergePrivateFields', () {
    test('private value wins; public old copy used only when private is empty', () {
      final merged = mergePrivateFields(
        {'shopName': 'S', 'phone': 'old', 'email': 'old@x', 'address': 'Old road'},
        {'phone': 'new', 'email': '  ', 'withdrawableBalance': 0},
        kVendorPrivateKeys,
      );
      expect(merged['shopName'], 'S');
      expect(merged['phone'], 'new');
      expect(merged['email'], 'old@x'); // blank private -> old copy
      expect(merged['address'], 'Old road');
      expect(merged['withdrawableBalance'], 0); // 0 is a value, not "empty"
    });

    test('no private doc (customer, rules not deployed): public data unchanged', () {
      final merged = mergePrivateFields({'shopName': 'S'}, null, kVendorPrivateKeys);
      expect(merged, {'shopName': 'S'});
    });

    test('non-private keys in the private doc are ignored', () {
      final merged = mergePrivateFields({'status': 'approved'}, {'status': 'pending'}, kVendorPrivateKeys);
      expect(merged['status'], 'approved');
    });
  });

  group('storagePathFromUrlOrPath', () {
    test('download link -> decoded path, token dropped', () {
      const url = 'https://firebasestorage.googleapis.com/v0/b/chalakchar-mart.firebasestorage.app/o/'
          'vendors%2Fabc%2Fdocuments%2Fnid-front-1.jpeg?alt=media&token=SECRET';
      final path = storagePathFromUrlOrPath(url);
      expect(path, 'vendors/abc/documents/nid-front-1.jpeg');
      expect(path.contains('SECRET'), isFalse);
    });
    test('a path stays a path; empty / foreign URL -> empty', () {
      expect(storagePathFromUrlOrPath('vendors/abc/documents/x.jpeg'), 'vendors/abc/documents/x.jpeg');
      expect(storagePathFromUrlOrPath(''), '');
      expect(storagePathFromUrlOrPath(null), '');
      expect(storagePathFromUrlOrPath('https://example.com/a.jpg'), '');
    });
  });

  group('vendorDocumentPath', () {
    test('prefers *Path, falls back to the path inside the old link', () {
      expect(vendorDocumentPath({'nidFrontPath': 'p/new.jpeg', 'nidFront': 'https://x/o/p%2Fold.jpeg?token=t'}, 'nidFront'),
          'p/new.jpeg');
      expect(vendorDocumentPath({'nidFront': 'https://x/v0/b/bk/o/p%2Fold.jpeg?token=t'}, 'nidFront'), 'p/old.jpeg');
      expect(vendorDocumentPath(null, 'nidBack'), '');
    });
  });

  test('pickKeys / withoutKeys split a form into private and public parts', () {
    final form = {'shopName': 'S', 'phone': '017', 'commissionPercent': 10};
    expect(pickKeys(form, kVendorPrivateKeys), {'phone': '017', 'commissionPercent': 10});
    expect(withoutKeys(form, kVendorPrivateKeys), {'shopName': 'S'});
  });
}
