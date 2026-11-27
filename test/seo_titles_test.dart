import 'package:chalakchar_mart/services/seo_titles.dart';
import 'package:chalakchar_mart/services/web_seo_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(WebSeoService.debugReset);

  group('SeoTitles', () {
    test('home title is the index.html title', () {
      expect(SeoTitles.homeTitle,
          'ChalakChar Mart | মোবাইল ও ল্যাপটপ পার্টস অনলাইন — ক্যাশ অন ডেলিভারি');
    });

    test('category title: English, server pattern', () {
      expect(SeoTitles.categoryTitle('Motherboard'),
          'Motherboard Price in Bangladesh | ChalakChar Mart');
      expect(SeoTitles.categoryTitle('  Mobile Parts '),
          'Mobile Parts Price in Bangladesh | ChalakChar Mart');
    });

    test('category title is cut to 65 like limitText', () {
      final title = SeoTitles.categoryTitle('Laptop & Desktop Computer Accessories Extra');
      expect(title.length, lessThanOrEqualTo(65));
      expect(title, endsWith('...'));
      expect(title,
          '${'Laptop & Desktop Computer Accessories Extra Price in Bangladesh | ChalakChar Mart'.substring(0, 62).trim()}...');
    });

    test('category title keeps & as is', () {
      expect(SeoTitles.categoryTitle('Toys & Games'),
          'Toys & Games Price in Bangladesh | ChalakChar Mart');
    });

    test('category description: own text first, else default sentence', () {
      expect(SeoTitles.categoryDescription('Motherboard'),
          'ChalakChar Mart থেকে Motherboard কিনুন — মডেল মিলিয়ে অর্ডার, ক্যাশ অন ডেলিভারি, সারা বাংলাদেশে হোম ডেলিভারি।');
      expect(SeoTitles.categoryDescription('X', '  Own   text '), 'Own text');
      expect(SeoTitles.categoryDescription('X', 'a' * 200).length, 160);
    });

    test('limitText collapses whitespace and cuts with ...', () {
      expect(SeoTitles.limitText('  a \n b  ', 10), 'a b');
      expect(SeoTitles.limitText('abcdefghij', 10), 'abcdefghij');
      expect(SeoTitles.limitText('abcdefghijk', 10), 'abcdefg...');
      expect(SeoTitles.limitText('abcdef ghijk', 10), 'abcdef...');
    });

    test('nameFromSlug', () {
      expect(SeoTitles.nameFromSlug('mobile-parts'), 'Mobile Parts');
      expect(SeoTitles.nameFromSlug('computer-accessories'), 'Computer Accessories');
    });
  });

  group('WebSeoService.pageTextForPath', () {
    test('home', () {
      expect(WebSeoService.pageTextForPath('/').title, SeoTitles.homeTitle);
      expect(WebSeoService.pageTextForPath('').title, SeoTitles.homeTitle);
    });

    test('policy pages, with or without trailing slash', () {
      expect(WebSeoService.pageTextForPath('/about-us').title, 'About Us | ChalakChar Mart');
      expect(WebSeoService.pageTextForPath('/return-policy/').title,
          'Return & Refund Policy | ChalakChar Mart');
    });

    test('category from slug until the real name is known', () {
      expect(WebSeoService.pageTextForPath('/category/mobile-parts').title,
          'Mobile Parts Price in Bangladesh | ChalakChar Mart');
    });

    test('category uses the learned real name afterwards', () {
      WebSeoService.debugIsWeb = true;
      WebSeoService.debugDom = _NullDom();
      WebSeoService.setCategorySeo(slug: 'tv-and-audio', name: 'TV & Audio');
      expect(WebSeoService.pageTextForPath('/category/tv-and-audio').title,
          'TV & Audio Price in Bangladesh | ChalakChar Mart');
    });

    test('cart, login and unknown app routes get the site name', () {
      for (final p in ['/cart', '/login', '/admin', '/x/y']) {
        expect(WebSeoService.pageTextForPath(p).title, 'ChalakChar Mart', reason: p);
        expect(WebSeoService.pageTextForPath(p).description, SeoTitles.homeDescription);
      }
    });
  });

  group('WebSeoService.currentTitle', () {
    test('off web: site name', () {
      WebSeoService.debugIsWeb = false;
      expect(WebSeoService.currentTitle, 'ChalakChar Mart');
    });

    test('before any write: the title the server sent', () {
      WebSeoService.debugIsWeb = true;
      WebSeoService.debugDom = _NullDom(served: 'Motherboard Price in Bangladesh | ChalakChar Mart');
      expect(WebSeoService.currentTitle, 'Motherboard Price in Bangladesh | ChalakChar Mart');
    });

    test('category not found (yet) keeps the title the server sent', () {
      // An empty first snapshot in a crawler's renderer must not turn a
      // real category page into "Page not found".
      WebSeoService.debugIsWeb = true;
      WebSeoService.debugDom = _NullDom(served: 'Mobile Parts Price in Bangladesh | ChalakChar Mart');
      WebSeoService.setCategorySeo(slug: 'mobile-parts', name: '', exists: false);
      expect(WebSeoService.currentTitle, 'Mobile Parts Price in Bangladesh | ChalakChar Mart');
    });

    test('server answered 404: its "not found" title is put back over the slug title', () {
      WebSeoService.debugIsWeb = true;
      WebSeoService.debugDom = _NullDom(served: SeoTitles.notFoundTitle);
      WebSeoService.resetPageSeo('/category/doesnotexist'); // route observer
      expect(WebSeoService.currentTitle, 'Doesnotexist Price in Bangladesh | ChalakChar Mart');
      WebSeoService.setCategorySeo(slug: 'doesnotexist', name: '', exists: false);
      expect(WebSeoService.currentTitle, SeoTitles.notFoundTitle);
    });
  });

  group('SeoTitles.productTitle (same rule as functions/seo/pages.js)', () {
    test('name cut short by the import: full name + site name', () {
      expect(
        SeoTitles.productTitle(
          '6.6" LCD Display For Samsung Galaxy A14 4G 5G A145F A145P A146P A146B A146U LCD',
          '6.6" LCD Display For Samsung Galaxy A14 4G 5G A145F A145P',
        ),
        '6.6" LCD Display For Samsung Galaxy A14 4G 5G A145F A145P A146P A146B A146U LCD | ChalakChar Mart',
      );
    });

    test('admin-written metaTitle wins', () {
      expect(SeoTitles.productTitle('iPhone 12 LCD', 'iPhone 12 LCD Display'), 'iPhone 12 LCD Display');
    });

    test('entities decoded once, no metaTitle', () {
      expect(SeoTitles.productTitle('6.6&quot; A &amp; B', null), '6.6" A & B | ChalakChar Mart');
    });
  });
}

class _NullDom extends SeoDom {
  final String served;
  _NullDom({this.served = ''});

  @override
  void setDocumentTitle(String title) {}
  @override
  String getDocumentTitle() => served;
  @override
  void setMetaByName(String name, String content) {}
  @override
  void setMetaByProperty(String property, String content) {}
  @override
  void setCanonical(String url) {}
}
