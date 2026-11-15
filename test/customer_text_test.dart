import 'package:chalakchar_mart/utils/customer_text.dart';
import 'package:chalakchar_mart/utils/variant_display_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('origin specifications are hidden, real ones kept', () {
    expect(isHiddenSpecification('Origin', 'Mainland China'), isTrue);
    expect(isHiddenSpecification('Place Of Origin', 'Guangdong'), isTrue);
    expect(isHiddenSpecification('Ships From', 'CN'), isTrue);
    expect(isHiddenSpecification('Brand Name', 'Netac'), isFalse);
    expect(isHiddenSpecification('Interface', 'SATA III'), isFalse);
  });

  test('sentences naming the supplier or China are dropped, the rest kept', () {
    expect(
      stripSupplierSentences(
          'Fast 2.5 inch SSD. We mainly ship via AliExpress standard shipping. Items cannot be tracked after they leave China! 3 year warranty.'),
      'Fast 2.5 inch SSD. 3 year warranty.',
    );
    expect(stripSupplierSentences('Netac SSD 128GB'), 'Netac SSD 128GB');
  });

  test('HTML: only the offending text runs change, tags stay', () {
    const html = '<p>Great display.</p><p>Delivery from AliExpress official warehouse.</p><img src="a.jpg">';
    final out = stripSupplierSentencesHtml(html);
    expect(out, '<p>Great display.</p><p></p><img src="a.jpg">');
    expect(mentionsSupplier(out), isFalse);
  });

  test('cart/order variant labels lose the ship-from part', () {
    expect(cleanVariantDisplayName('OEM No Frame / China Mainland'), 'OEM No Frame');
    expect(cleanVariantDisplayName('128GB'), '128GB');
  });
}
