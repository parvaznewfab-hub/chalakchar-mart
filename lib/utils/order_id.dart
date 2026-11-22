/// Short order number for screens, invoices and messages: the first 8
/// characters of the order id, or the whole id when it is shorter (an id
/// shorter than 8 used to throw a RangeError and grey out the admin list).
String shortOrderId(String id) {
  final t = id.trim();
  return t.length > 8 ? t.substring(0, 8) : t;
}
