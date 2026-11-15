import 'package:chalakchar_mart/utils/image_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ali = 'https://ae01.alicdn.com/kf/Sad0475f27c7d4379a13d784c615d4bbda.jpg';

  test('AliExpress CDN images get a resized WebP copy of at least the size asked', () {
    expect(sizedImageUrl(ali, 480), '${ali}_480x480q75.jpg_.webp');
    expect(sizedImageUrl(ali, 300), '${ali}_350x350q75.jpg_.webp');
    expect(sizedImageUrl(ali, 72), '${ali}_120x120q75.jpg_.webp');
    expect(sizedImageUrl(ali, 5000), '${ali}_960x960q75.jpg_.webp');
  });

  test('an existing transcoding suffix is replaced, not stacked', () {
    expect(sizedImageUrl('${ali}_220x220.jpg_.avif', 480), '${ali}_480x480q75.jpg_.webp');
    expect(sizedImageUrl('//ae01.alicdn.com/kf/a.png', 220), 'https://ae01.alicdn.com/kf/a.png_220x220q75.jpg_.webp');
  });

  test('other hosts and unusual AliExpress URLs are left as they are', () {
    const storage = 'https://firebasestorage.googleapis.com/v0/b/x/o/products%2F1.jpg?alt=media&token=t';
    expect(sizedImageUrl(storage, 480), storage);
    expect(sizedImageUrl('https://ae01.alicdn.com/kf/a.gif', 480), 'https://ae01.alicdn.com/kf/a.gif');
    expect(sizedImageUrl('https://ae01.alicdn.com/kf/a.jpg?x=1', 480), 'https://ae01.alicdn.com/kf/a.jpg?x=1');
    expect(sizedImageUrl('', 480), '');
    expect(sizedImageUrl(null, 480), '');
  });
}
