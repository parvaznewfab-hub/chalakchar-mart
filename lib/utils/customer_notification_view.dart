/// How a customer notification doc is shown and where a tap leads.
///
/// Older docs were written in English ("Order Update", "Product found! 🎉")
/// and are shown in Bangla here; the Firestore data itself is not changed.
/// Newer docs already carry Bangla text, which is shown as it is.
library;

enum NotificationCategory { order, newProduct, offer, general }

class CustomerNotificationView {
  final String title;
  final String body;
  final NotificationCategory category;

  /// Bangla label instead of raw types like "general" / "new_product".
  final String label;

  /// Product to open, if any (top-level productId, data.productId, or the
  /// first of data.productIds).
  final String productId;

  /// Order to open, if any.
  final String orderId;

  const CustomerNotificationView({
    required this.title,
    required this.body,
    required this.category,
    required this.label,
    required this.productId,
    required this.orderId,
  });

  bool get hasTarget => productId.isNotEmpty || orderId.isNotEmpty;

  static const Map<String, String> orderStatusBn = {
    'pending': 'অপেক্ষমাণ',
    'confirmed': 'নিশ্চিত করা হয়েছে',
    'processing': 'প্রস্তুত হচ্ছে',
    'ready_for_pickup': 'পাঠানোর জন্য প্রস্তুত',
    'assigned_to_rider': 'ডেলিভারি কর্মীকে দেওয়া হয়েছে',
    'assigned': 'ডেলিভারি কর্মীকে দেওয়া হয়েছে',
    'picked_up': 'পথে আছে',
    'on_the_way': 'পথে আছে',
    'out_for_delivery': 'পথে আছে',
    'delivered': 'ডেলিভারি হয়েছে',
    'cancelled': 'বাতিল করা হয়েছে',
    'returned': 'ফেরত এসেছে',
    'rejected': 'বাতিল করা হয়েছে',
  };

  static final RegExp _bangla = RegExp(r'[ঀ-৿]');

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

  static NotificationCategory categoryFor(String type, String stored) {
    switch (stored) {
      case 'order':
        return NotificationCategory.order;
      case 'new_product':
        return NotificationCategory.newProduct;
      case 'offer':
        return NotificationCategory.offer;
    }
    if (type.startsWith('order') || type == 'picked_up') {
      return NotificationCategory.order;
    }
    if (const {'wishlist_discount', 'offer', 'broadcast', 'promo', 'price_drop'}.contains(type)) {
      return NotificationCategory.offer;
    }
    if (const {'new_product', 'search_import_done', 'back_in_stock'}.contains(type)) {
      return NotificationCategory.newProduct;
    }
    return NotificationCategory.general;
  }

  static String labelFor(NotificationCategory c) {
    switch (c) {
      case NotificationCategory.order:
        return 'অর্ডার';
      case NotificationCategory.newProduct:
        return 'নতুন পণ্য';
      case NotificationCategory.offer:
        return 'অফার';
      case NotificationCategory.general:
        return 'বার্তা';
    }
  }

  factory CustomerNotificationView.fromDoc(Map<String, dynamic> doc) {
    final raw = doc['data'];
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    final type = _s(doc['type']).isNotEmpty ? _s(doc['type']) : _s(data['type']);
    final category = categoryFor(type, _s(doc['category']));

    var productId = _s(doc['productId']);
    if (productId.isEmpty) productId = _s(data['productId']);
    if (productId.isEmpty && data['productIds'] is List && (data['productIds'] as List).isNotEmpty) {
      productId = _s((data['productIds'] as List).first);
    }
    var orderId = _s(doc['orderId']);
    if (orderId.isEmpty) orderId = _s(data['orderId']);

    var title = _s(doc['title']);
    var body = _s(doc['body']);

    // English text from older docs -> Bangla (display only).
    if (!_bangla.hasMatch(title)) {
      final translated = _translate(type, data, orderId, title, body);
      if (translated != null) {
        title = translated.$1;
        body = translated.$2;
      }
    }
    if (title.isEmpty) title = 'নোটিফিকেশন';

    return CustomerNotificationView(
      title: title,
      body: body,
      category: category,
      label: labelFor(category),
      productId: productId,
      orderId: orderId,
    );
  }

  static (String, String)? _translate(
    String type,
    Map<String, dynamic> data,
    String orderId,
    String title,
    String body,
  ) {
    final name = _s(data['productName']);
    final id = _short(orderId);
    switch (type) {
      case 'order_status':
        final status = _s(data['status']);
        return ('অর্ডার আপডেট', 'আপনার অর্ডার #$id এখন: ${orderStatusBn[status] ?? status}।');
      case 'picked_up':
        return ('অর্ডার পথে আছে 🚚', 'আপনার অর্ডার #$id রওনা হয়েছে।');
      case 'order_delivered':
        return ('অর্ডার ডেলিভারি হয়েছে ✅', 'আপনার অর্ডার #$id সফলভাবে ডেলিভারি হয়েছে।');
      case 'order':
        return ('অর্ডার করা হয়েছে 🛒', 'আপনার অর্ডার #$id গ্রহণ করা হয়েছে।');
      case 'search_import_done':
        final query = _s(data['query']);
        final what = name.isNotEmpty ? name : (query.isNotEmpty ? '"$query"' : 'আপনি যে পণ্যটি খুঁজছিলেন সেটি');
        return ('আপনার খোঁজা পণ্য পাওয়া গেছে! 🎉', '$what এখন পাওয়া যাচ্ছে। দেখতে চাপুন।');
      case 'back_in_stock':
        return ('পছন্দের পণ্য আবার স্টকে 📦', '${name.isNotEmpty ? name : 'আপনার পছন্দের পণ্য'} আবার পাওয়া যাচ্ছে।');
      case 'wishlist_discount':
        final pct = _s(data['discountPercent']);
        return (
          'পছন্দের পণ্যে ছাড় 🏷️',
          '${name.isNotEmpty ? name : 'আপনার পছন্দের পণ্য'}-এ এখন ${pct.isNotEmpty ? '$pct% ' : ''}ছাড়।',
        );
      case 'new_product':
        return ('নতুন পণ্য এসেছে 🛒', body.isNotEmpty ? body : name);
    }
    return null;
  }

  /// "এইমাত্র", "5 মিনিট আগে", ... then the date.
  static String timeAgo(DateTime? at, {DateTime? now}) {
    if (at == null) return '';
    final n = now ?? DateTime.now();
    final d = n.difference(at);
    if (d.inMinutes < 1) return 'এইমাত্র';
    if (d.inMinutes < 60) return '${d.inMinutes} মিনিট আগে';
    if (d.inHours < 24) return '${d.inHours} ঘণ্টা আগে';
    if (d.inDays < 7) return '${d.inDays} দিন আগে';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.day)}-${two(at.month)}-${at.year}';
  }
}
