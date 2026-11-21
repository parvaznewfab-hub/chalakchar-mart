/// Page titles and descriptions the app writes into the document head.
///
/// They mirror what the server sends in the first HTML so the tab title and
/// meta tags don't change once Flutter starts:
/// - home: web/index.html
/// - category and policy pages: pageSeo / POLICY_PAGE_SEO in functions/index.js
/// test/seo_titles_parity_test.dart reads both files and fails on drift.
///
/// Product titles are not here: product pages keep setting their own
/// (WebSeoService.setProductSeo).
class SeoTitles {
  SeoTitles._();

  static const String siteName = 'ChalakChar Mart';

  static const String homeTitle =
      'ChalakChar Mart | মোবাইল ও ল্যাপটপ পার্টস অনলাইন — ক্যাশ অন ডেলিভারি';
  static const String homeDescription =
      'মোবাইল ও ল্যাপটপ পার্টস, ডিসপ্লে, ব্যাটারি, মাদারবোর্ড ও কম্পিউটার এক্সেসরিজ অনলাইনে কিনুন। ক্যাশ অন ডেলিভারি, সারা বাংলাদেশে হোম ডেলিভারি।';

  static const String notFoundTitle = 'Page not found | ChalakChar Mart';
  static const String notFoundDescription =
      'এই পেজটি পাওয়া যায়নি। ChalakChar Mart-এ মোবাইল ও ল্যাপটপ পার্টস, কম্পিউটার এক্সেসরিজ ও অন্যান্য পণ্য দেখুন।';

  /// Same keys, titles and descriptions as POLICY_PAGE_SEO (functions/index.js).
  static const Map<String, SeoPageText> policyPages = {
    '/about-us': SeoPageText(
      title: 'About Us | ChalakChar Mart',
      description:
          'ChalakChar Mart — চালাকচর বাজার, মনোহরদী, নরসিংদীর অনলাইন শপ। মোবাইল ও ল্যাপটপ পার্টস, কম্পিউটার এক্সেসরিজ ও দৈনন্দিন পণ্য, ক্যাশ অন ডেলিভারিতে সারা দেশে।',
    ),
    '/privacy-policy': SeoPageText(
      title: 'Privacy Policy | ChalakChar Mart',
      description:
          'ChalakChar Mart কোন তথ্য সংগ্রহ করে, কীভাবে ব্যবহার ও সুরক্ষিত রাখে, এবং আপনার তথ্য দেখা, সংশোধন বা মুছে ফেলার অনুরোধ যেভাবে করবেন।',
    ),
    '/terms-conditions': SeoPageText(
      title: 'Terms & Conditions | ChalakChar Mart',
      description:
          'ChalakChar Mart-এ অর্ডার, দাম, পেমেন্ট, ডেলিভারি, পণ্যের সামঞ্জস্য ও অ্যাকাউন্ট ব্যবহারের শর্তাবলী।',
    ),
    '/return-policy': SeoPageText(
      title: 'Return & Refund Policy | ChalakChar Mart',
      description:
          'পণ্য ফেরত, রিপ্লেসমেন্ট, ওয়ারেন্টি ও রিফান্ডের নিয়ম — মোবাইল ও ল্যাপটপ পার্টস হাতে পেয়ে কী করবেন এবং কখন রিপ্লেসমেন্ট পাবেন।',
    ),
    '/data-deletion': SeoPageText(
      title: 'Data Deletion | ChalakChar Mart',
      description:
          'ChalakChar Mart অ্যাকাউন্ট ও ব্যক্তিগত তথ্য মুছে ফেলার অনুরোধ যেভাবে করবেন।',
    ),
  };

  /// pageSeo's category title: limitText(`${name} Price in Bangladesh | ChalakChar Mart`, 65).
  static String categoryTitle(String name) =>
      limitText('${name.trim()} Price in Bangladesh | $siteName', 65);

  /// pageSeo's category description: the category's own description, else
  /// the default sentence; limitText(..., 160).
  static String categoryDescription(String name, [String? description]) {
    final own = (description ?? '').trim();
    return limitText(
      own.isNotEmpty
          ? own
          : '$siteName থেকে ${name.trim()} কিনুন — মডেল মিলিয়ে অর্ডার, ক্যাশ অন ডেলিভারি, সারা বাংলাদেশে হোম ডেলিভারি।',
      160,
    );
  }

  /// "mobile-parts" -> "Mobile Parts": used until the category's real name
  /// has loaded (same rule as the category page's app bar).
  static String nameFromSlug(String slug) => slug
      .split(RegExp(r'[-_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// functions/index.js limitText: collapse whitespace; if longer than
  /// [max], cut to max-3, trim, add "...". Lengths are UTF-16 code units in
  /// both JS and Dart.
  static String limitText(String value, int max) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= max) return text;
    final cut = max - 3 < 0 ? 0 : max - 3;
    return '${text.substring(0, cut).trim()}...';
  }
}

class SeoPageText {
  final String title;
  final String description;

  const SeoPageText({required this.title, required this.description});
}
