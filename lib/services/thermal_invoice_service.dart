import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class ThermalInvoiceService {
  static Future<void> printOrderReceipt({
    required String printerIp,
    int port = 9100,
    required String orderId,
    required Map<String, dynamic> order,
    required Map<String, double> breakdown,
  }) async {
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(PaperSize.mm80, profile);

    final PosPrintResult res = await printer.connect(printerIp, port: port);

    if (res != PosPrintResult.success) {
      throw Exception('Printer connection failed: ${res.msg}');
    }

    final address = order['address'] as Map? ?? {};
    final items = order['items'] as List? ?? [];

    printer.text(
      'ChalakChar Mart',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );

    printer.text(
      'Chalak Char, Monohardi, Narsingdi',
      styles: const PosStyles(align: PosAlign.center),
    );

    printer.text(
      'abdullahpharmacy.com',
      styles: const PosStyles(align: PosAlign.center),
    );

    printer.hr();

    printer.row([
      PosColumn(text: 'Invoice:', width: 4),
      PosColumn(text: '#${orderId.substring(0, 8)}', width: 8),
    ]);

    printer.row([
      PosColumn(text: 'Customer:', width: 4),
      PosColumn(text: '${order['userName'] ?? 'User'}', width: 8),
    ]);

    printer.row([
      PosColumn(text: 'Phone:', width: 4),
      PosColumn(text: '${address['phone'] ?? 'N/A'}', width: 8),
    ]);

    printer.hr();

    for (final item in items) {
      final name = item['name'] ?? '';
      final unit = (item['unit'] ?? '').toString();
      final qty = int.tryParse((item['qty'] ?? 1).toString()) ?? 1;
      final price = double.tryParse((item['price'] ?? 0).toString()) ?? 0;
      final total = qty * price;

      printer.text(
        unit.isEmpty ? name.toString() : '${name.toString()} ($unit)',
        styles: const PosStyles(bold: true),
      );

      printer.row([
        PosColumn(text: '$qty x ${price.toStringAsFixed(2)}', width: 6),
        PosColumn(
          text: '${total.toStringAsFixed(2)} Tk',
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    printer.hr();

    _totalRow(printer, 'MRP', breakdown['totalMrp']);
    _totalRow(printer, 'Discount', -((breakdown['productDiscount'] ?? 0)));
    _totalRow(printer, 'Coupon', -((breakdown['couponDiscount'] ?? 0)));
    _totalRow(printer, 'ChalakChar Mart Cash', -((breakdown['abdCashUsed'] ?? 0)));
    _totalRow(printer, 'Delivery', breakdown['deliveryCharge']);

    printer.hr(ch: '=');

    _totalRow(
      printer,
      'TOTAL',
      breakdown['grandTotal'],
      bold: true,
    );

    printer.hr();

    printer.text(
      'Thank you for choosing ChalakChar Mart!',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );

    printer.feed(2);
    printer.cut();
    printer.disconnect();
  }

  static void _totalRow(
      NetworkPrinter printer,
      String title,
      dynamic value, {
        bool bold = false,
      }) {
    final amount = double.tryParse((value ?? 0).toString()) ?? 0;

    printer.row([
      PosColumn(
        text: title,
        width: 6,
        styles: PosStyles(bold: bold),
      ),
      PosColumn(
        text: '${amount.toStringAsFixed(2)} Tk',
        width: 6,
        styles: PosStyles(
          align: PosAlign.right,
          bold: bold,
        ),
      ),
    ]);
  }
}


