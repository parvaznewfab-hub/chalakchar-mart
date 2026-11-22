import 'package:chalakchar_mart/utils/order_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short order id never throws', () {
    expect(shortOrderId('abcdefghijklmnopqrst'), 'abcdefgh');
    expect(shortOrderId('abc'), 'abc');
    expect(shortOrderId(''), '');
    expect(shortOrderId('12345678'), '12345678');
  });
}
