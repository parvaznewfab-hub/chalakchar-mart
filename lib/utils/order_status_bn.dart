/// Order progress steps in Bangla, shared by My Orders and Track Order so
/// both pages use the same words and the same step for a status.
library;

const List<String> orderStepsBn = [
  'অর্ডার করা হয়েছে',
  'প্রস্তুত',
  'ডেলিভারি কর্মী নির্ধারিত',
  'সংগ্রহ করা হয়েছে',
  'পথে আছে',
  'ডেলিভারি হয়েছে',
];

/// Index into [orderStepsBn]; -1 for a cancelled/rejected order.
int orderStepIndex(String status, [String deliveryStatus = '']) {
  if (status == 'cancelled' || status == 'rejected') return -1;
  if (status == 'delivered' || deliveryStatus == 'delivered') return 5;
  if (deliveryStatus == 'on_the_way' || status == 'on_the_way') return 4;
  if (deliveryStatus == 'picked_up' || status == 'picked_up') return 3;
  if (deliveryStatus == 'assigned' || status == 'assigned_to_rider') return 2;
  if (status == 'ready_for_pickup' || status == 'confirmed') return 1;
  return 0;
}

const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// 12 -> "১২"
String bnNumber(int n) => n.toString().split('').map((c) {
      final d = int.tryParse(c);
      return d == null ? c : _bnDigits[d];
    }).join();
