import 'package:chalakchar_mart/widgets/global_web_header.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('header logo is 56px and fits the main bar without growing it', () {
    expect(GlobalWebHeader.logoHeight, 56);
    // logo + _HoverBox padding (4 top + 4 bottom) must stay inside the bar.
    expect(GlobalWebHeader.logoHeight + 8, lessThanOrEqualTo(GlobalWebHeader.mainBarHeight));
    // 900x240 logo at 56px high is 210 wide: the reserved box fits it exactly.
    expect(GlobalWebHeader.logoBoxWidth, closeTo(900 / 240 * 56, 0.5));
  });
}
