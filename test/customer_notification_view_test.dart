import 'package:chalakchar_mart/utils/customer_notification_view.dart';
import 'package:chalakchar_mart/widgets/customer_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('old English docs are shown in Bangla (data unchanged)', () {
    test('Product found -> names the query, links first product', () {
      final v = CustomerNotificationView.fromDoc({
        'title': 'Product found! 🎉',
        'body': 'The product you searched for is now available.',
        'data': {
          'type': 'search_import_done',
          'query': 'ssd',
          'productIds': ['p1', 'p2'],
        },
      });
      expect(v.title, 'আপনার খোঁজা পণ্য পাওয়া গেছে! 🎉');
      expect(v.body, contains('"ssd"'));
      expect(v.productId, 'p1');
      expect(v.label, 'নতুন পণ্য');
    });

    test('Order Update -> Bangla status, opens order', () {
      final v = CustomerNotificationView.fromDoc({
        'title': 'Order Update',
        'body': 'Your order #abcdefgh is now confirmed',
        'data': {'type': 'order_status', 'orderId': 'abcdefghXYZ', 'status': 'confirmed'},
      });
      expect(v.title, 'অর্ডার আপডেট');
      expect(v.body, 'আপনার অর্ডার #abcdefgh এখন: নিশ্চিত করা হয়েছে।');
      expect(v.orderId, 'abcdefghXYZ');
      expect(v.label, 'অর্ডার');
    });

    test('wishlist discount -> offer label', () {
      final v = CustomerNotificationView.fromDoc({
        'type': 'wishlist_discount',
        'title': 'Wishlist product discount 🏷️',
        'body': 'Fan now has 15% discount.',
        'data': {'type': 'wishlist_discount', 'productId': 'f1', 'productName': 'Fan', 'discountPercent': '15'},
      });
      expect(v.label, 'অফার');
      expect(v.body, 'Fan-এ এখন 15% ছাড়।');
    });
  });

  test('Bangla docs are shown as stored; top-level link wins', () {
    final v = CustomerNotificationView.fromDoc({
      'type': 'new_product',
      'title': 'নতুন পণ্য এসেছে 🛒',
      'body': 'Mini SD Card Reader',
      'productId': 'top',
      'data': {'type': 'new_product', 'productId': 'inner'},
    });
    expect(v.title, 'নতুন পণ্য এসেছে 🛒');
    expect(v.body, 'Mini SD Card Reader');
    expect(v.productId, 'top');
  });

  test('no raw type label is ever shown', () {
    final v = CustomerNotificationView.fromDoc({'title': 'Hello', 'body': 'x'});
    expect(v.label, 'বার্তা');
    expect(v.hasTarget, isFalse);
    expect(v.title, 'Hello');
  });

  test('product availability', () {
    expect(NotificationActions.isProductAvailable(null), isFalse);
    expect(NotificationActions.isProductAvailable({}), isTrue);
    expect(NotificationActions.isProductAvailable({'isActive': false}), isFalse);
    expect(NotificationActions.isProductAvailable({'isVisible': false}), isFalse);
    expect(NotificationActions.isProductAvailable({'isPublished': false}), isFalse);
    expect(NotificationActions.isProductAvailable({'hiddenReason': 'health_removed'}), isFalse);
    expect(NotificationActions.isProductAvailable({'approvalStatus': 'pending'}), isFalse);
    expect(NotificationActions.isProductAvailable({'approvalStatus': 'approved'}), isTrue);
  });

  test('time ago', () {
    final now = DateTime(2026, 11, 16, 12);
    expect(CustomerNotificationView.timeAgo(now, now: now), 'এইমাত্র');
    expect(CustomerNotificationView.timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 মিনিট আগে');
    expect(CustomerNotificationView.timeAgo(DateTime(2026, 10, 1), now: now), '01-10-2026');
  });
}
