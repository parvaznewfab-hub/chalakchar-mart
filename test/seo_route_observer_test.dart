import 'package:chalakchar_mart/services/seo_route_observer.dart';
import 'package:chalakchar_mart/services/seo_titles.dart';
import 'package:chalakchar_mart/services/web_seo_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records head writes instead of touching a DOM.
class FakeSeoDom extends SeoDom {
  String title;
  final Map<String, String> byName = {};
  final Map<String, String> byProperty = {};
  String canonical = '';

  FakeSeoDom({this.title = ''});

  @override
  void setDocumentTitle(String t) => title = t;
  @override
  String getDocumentTitle() => title;
  @override
  void setMetaByName(String name, String content) => byName[name] = content;
  @override
  void setMetaByProperty(String property, String content) =>
      byProperty[property] = content;
  @override
  void setCanonical(String url) => canonical = url;
}

Widget _app({
  required GlobalKey<NavigatorState> navKey,
  ThemeMode themeMode = ThemeMode.light,
}) {
  Widget page(String label) => Scaffold(body: Text(label));
  return MaterialApp(
    navigatorKey: navKey,
    navigatorObservers: [SeoRouteObserver()],
    onGenerateTitle: (_) => WebSeoService.currentTitle,
    themeMode: themeMode,
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    routes: {
      '/': (_) => page('home'),
      '/about-us': (_) => page('about'),
      '/cart': (_) => page('cart'),
      '/login': (_) => page('login'),
    },
    onGenerateRoute: (settings) => MaterialPageRoute(
      settings: settings,
      builder: (_) => page(settings.name ?? ''),
    ),
  );
}

void main() {
  late FakeSeoDom fake;
  late List<String> switcherLabels;

  setUp(() {
    fake = FakeSeoDom();
    WebSeoService.debugIsWeb = true;
    WebSeoService.debugDom = fake;
    switcherLabels = [];
    // MaterialApp's Title widget reports its title here; on web the engine
    // turns it into document.title.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
        switcherLabels.add((call.arguments as Map)['label'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    WebSeoService.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('home after a product page: every product tag replaced', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navKey: navKey));

    // What setProductSeo leaves in the head on a product page.
    navKey.currentState!.pushNamed('/product/abc');
    await tester.pumpAndSettle();
    fake
      ..title = 'iPhone 12 LCD | Buy Online - ChalakChar Mart'
      ..canonical = 'https://chalakcharmart.com/product/abc';
    fake.byName.addAll({
      'title': 'iPhone 12 LCD',
      'description': 'product description',
      'twitter:title': 'iPhone 12 LCD',
      'twitter:description': 'product description',
      'twitter:image': 'https://img/product.jpg',
    });
    fake.byProperty.addAll({
      'og:title': 'iPhone 12 LCD',
      'og:description': 'product description',
      'og:type': 'product',
      'og:url': 'https://chalakcharmart.com/product/abc',
      'og:image': 'https://img/product.jpg',
    });

    navKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(fake.title, SeoTitles.homeTitle);
    expect(fake.byName['title'], SeoTitles.homeTitle);
    expect(fake.byName['description'], SeoTitles.homeDescription);
    expect(fake.byName['twitter:title'], SeoTitles.homeTitle);
    expect(fake.byName['twitter:description'], SeoTitles.homeDescription);
    expect(fake.byName['twitter:image'], 'https://chalakcharmart.com/og-image-1200x630.png');
    expect(fake.byProperty['og:title'], SeoTitles.homeTitle);
    expect(fake.byProperty['og:description'], SeoTitles.homeDescription);
    expect(fake.byProperty['og:type'], 'website');
    expect(fake.byProperty['og:url'], 'https://chalakcharmart.com/');
    expect(fake.byProperty['og:image'], 'https://chalakcharmart.com/og-image-1200x630.png');
    expect(fake.canonical, 'https://chalakcharmart.com/');
  });

  testWidgets('product route: observer leaves the product page its own tags', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navKey: navKey));
    fake.title = 'set by product page';
    navKey.currentState!.pushNamed('/product/abc');
    await tester.pumpAndSettle();
    expect(fake.title, 'set by product page');
  });

  testWidgets('policy and category pages get the server titles', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navKey: navKey));

    navKey.currentState!.pushNamed('/about-us');
    await tester.pumpAndSettle();
    expect(fake.title, 'About Us | ChalakChar Mart');
    expect(fake.canonical, 'https://chalakcharmart.com/about-us');

    navKey.currentState!.pushNamed('/category/mobile-parts');
    await tester.pumpAndSettle();
    expect(fake.title, 'Mobile Parts Price in Bangladesh | ChalakChar Mart');
  });

  testWidgets('the app never writes robots (the server decides them)', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navKey: navKey));

    for (final path in ['/cart', '/login', '/about-us', '/category/mobile-parts', '/product/abc']) {
      navKey.currentState!.pushNamed(path);
      await tester.pumpAndSettle();
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
    }
    WebSeoService.setCategorySeo(slug: 'mobile-parts', name: '', exists: false);
    WebSeoService.setCategorySeo(slug: 'mobile-parts', name: 'Mobile Parts');
    WebSeoService.setProductSeo(
      product: {'name': 'Hidden product'},
      productId: 'hidden',
    );

    expect(fake.byName.containsKey('robots'), isFalse);
    expect(fake.title, isNot(SeoTitles.notFoundTitle));
  });

  testWidgets('root rebuild (theme switch) keeps the product title', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navKey: navKey));

    navKey.currentState!.pushNamed('/product/abc');
    await tester.pumpAndSettle();
    WebSeoService.setProductSeo(
      product: {'name': 'iPhone 12 LCD', 'metaTitle': 'iPhone 12 LCD Display'},
      productId: 'abc',
    );
    expect(WebSeoService.currentTitle, 'iPhone 12 LCD Display');

    switcherLabels.clear();
    await tester.pumpWidget(_app(navKey: navKey, themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    expect(switcherLabels, isNotEmpty, reason: 'MaterialApp rebuilt its Title');
    expect(switcherLabels.toSet(), {'iPhone 12 LCD Display'});
  });

  testWidgets('first build keeps the title the server sent', (tester) async {
    fake.title = 'Motherboard Price in Bangladesh | ChalakChar Mart';
    final navKey = GlobalKey<NavigatorState>();
    // No observer write happens before MaterialApp's first Title build.
    expect(WebSeoService.currentTitle, 'Motherboard Price in Bangladesh | ChalakChar Mart');
    await tester.pumpWidget(_app(navKey: navKey));
    expect(switcherLabels.first, 'Motherboard Price in Bangladesh | ChalakChar Mart');
  });
}
