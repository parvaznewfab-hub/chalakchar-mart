import 'package:flutter/foundation.dart';

import 'seo_titles.dart';
import 'web_seo_dom.dart' as dom;

/// The head writes [WebSeoService]'s page-level methods make; tests swap in
/// a fake through [WebSeoService.debugDom].
class SeoDom {
  const SeoDom();

  void setDocumentTitle(String title) => dom.setDocumentTitle(title);
  String getDocumentTitle() => dom.getDocumentTitle();
  void setMetaByName(String name, String content) =>
      dom.setMetaByName(name, content);
  void setMetaByProperty(String property, String content) =>
      dom.setMetaByProperty(property, content);
  void setCanonical(String url) => dom.setCanonical(url);
}

class WebSeoService {
  WebSeoService._();

  static const String siteName = 'ChalakChar Mart';
  static const String baseUrl = 'https://chalakcharmart.com';
  static const String _defaultImage = '$baseUrl/og-image-1200x630.png';

  @visibleForTesting
  static SeoDom? debugDom;
  @visibleForTesting
  static bool? debugIsWeb;

  static SeoDom get _dom => debugDom ?? const SeoDom();
  static bool get _isWeb => debugIsWeb ?? kIsWeb;

  static String? _currentTitle;

  /// The <title> the server sent with this page load, read before the app's
  /// first head write.
  static String? _servedTitle;

  /// Category names by URL slug, learned on category pages, so a category
  /// page reached again by Back gets its real name, not the slug's.
  static final Map<String, String> _categoryNames = {};

  /// The page title the app last set; before that, the title the server
  /// sent. MaterialApp.onGenerateTitle returns this, so a root rebuild
  /// (theme switch, ...) keeps the page's title instead of overwriting it.
  static String get currentTitle {
    final current = _currentTitle;
    if (current != null) return current;
    if (!_isWeb) return siteName;
    final served = _dom.getDocumentTitle().trim();
    return served.isEmpty ? siteName : served;
  }

  @visibleForTesting
  static void debugReset() {
    _currentTitle = null;
    _servedTitle = null;
    _categoryNames.clear();
    debugDom = null;
    debugIsWeb = null;
  }

  /// Title and description for a non-product [path], same as the server's
  /// HTML for it (see [SeoTitles]).
  static SeoPageText pageTextForPath(String path) {
    final clean = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    if (clean.isEmpty || clean == '/') {
      return const SeoPageText(
        title: SeoTitles.homeTitle,
        description: SeoTitles.homeDescription,
      );
    }
    final policy = SeoTitles.policyPages[clean];
    if (policy != null) return policy;

    final segments = Uri(path: clean).pathSegments;
    if (segments.length == 2 && segments.first == 'category') {
      final slug = _categorySlug(segments[1]);
      final name = _categoryNames[slug] ?? SeoTitles.nameFromSlug(slug);
      return SeoPageText(
        title: SeoTitles.categoryTitle(name),
        description: SeoTitles.categoryDescription(name),
      );
    }
    // /cart, /login and other app-only routes get index.html, whose
    // description is the home one.
    return const SeoPageText(
      title: siteName,
      description: SeoTitles.homeDescription,
    );
  }

  static String _categorySlug(String raw) {
    var value = raw;
    try {
      value = Uri.decodeComponent(raw);
    } catch (_) {}
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Writes every page-level head tag for a non-product page, so nothing a
  /// product page set (description, og:*, twitter:*, JSON-LD) is left behind.
  static void setPageSeo({
    required String path,
    required String title,
    required String description,
  }) {
    if (!_isWeb) return;
    final d = _dom;
    _servedTitle ??= d.getDocumentTitle().trim();
    final url = '$baseUrl${path.isEmpty ? '/' : path}';
    _currentTitle = title;
    d.setDocumentTitle(title);
    d.setMetaByName('title', title);
    d.setMetaByName('description', description);
    d.setMetaByProperty('og:title', title);
    d.setMetaByProperty('og:description', description);
    d.setMetaByProperty('og:type', 'website');
    d.setMetaByProperty('og:url', url);
    d.setMetaByProperty('og:image', _defaultImage);
    d.setMetaByName('twitter:title', title);
    d.setMetaByName('twitter:description', description);
    d.setMetaByName('twitter:image', _defaultImage);
    d.setCanonical(url);
  }

  /// Category page, once its real name is known (the route observer used
  /// the slug's name until then). [exists] false changes nothing: the
  /// server already sent the right head for a missing category (404 title,
  /// noindex), and a category the app has not found yet (an empty first
  /// snapshot while Firestore is still connecting, as in a crawler's
  /// renderer) must keep the server's title and robots.
  ///
  /// Robots belong to the server alone: the app never writes them.
  static void setCategorySeo({
    required String slug,
    required String name,
    String? description,
    bool exists = true,
  }) {
    if (!_isWeb) return;
    final path = '/category/${_categorySlug(slug)}';
    if (!exists) {
      // Only when the server itself answered "not found" for this page
      // load: put its 404 title back (the route observer wrote the slug's
      // name over it). Robots stay as the server sent them.
      if (_servedTitle == SeoTitles.notFoundTitle &&
          _currentTitle != SeoTitles.notFoundTitle) {
        setPageSeo(
          path: path,
          title: SeoTitles.notFoundTitle,
          description: SeoTitles.notFoundDescription,
        );
      }
      return;
    }
    _categoryNames[_categorySlug(slug)] = name.trim();
    final title = SeoTitles.categoryTitle(name);
    if (_currentTitle == title) return;
    setPageSeo(
      path: path,
      title: title,
      description: SeoTitles.categoryDescription(name, description),
    );
  }

  static String _text(dynamic value, [String fallback = '']) {
    final result = (value ?? '').toString().trim();
    return result.isEmpty ? fallback : result;
  }

  static String _firstImage(Map<String, dynamic> product) {
    final images = product['images'];
    if (images is List && images.isNotEmpty) {
      for (final item in images) {
        final url = _text(item);
        if (url.startsWith('http')) return url;
      }
    }

    final imageUrl = _text(product['imageUrl'] ?? product['image']);
    if (imageUrl.startsWith('http')) return imageUrl;

    return '$baseUrl/og-image-1200x630.png';
  }

  static String _cleanDescription(String value) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 155) return clean;
    return '${clean.substring(0, 152).trim()}...';
  }

  /// Head tags for a non-product [path] after in-app navigation: the same
  /// title/description the server sends for it, canonical for [path], and
  /// nothing left over from a product page.
  static void resetPageSeo(String path) {
    final text = pageTextForPath(path);
    setPageSeo(path: path, title: text.title, description: text.description);
  }

  static void setProductSeo({
    required Map<String, dynamic> product,
    required String productId,
  }) {
    if (!_isWeb) return;

    final productName = _text(product['name'], 'Product');
    // Same <title> as productSeo (functions/seo/pages.js productTitle).
    final metaTitle = SeoTitles.productTitle(product['name'], product['metaTitle']);

    final descriptionSource = _text(
      product['metaDescription'],
      _text(
        product['description'],
        _text(product['overview'], 'Buy $productName online from $siteName.'),
      ),
    );

    final metaDescription = _cleanDescription(descriptionSource);
    final url = '$baseUrl/product/$productId';
    final image = _firstImage(product);

    _currentTitle = metaTitle;
    dom.setDocumentTitle(metaTitle);
    dom.setMetaByName('title', metaTitle);
    dom.setMetaByName('description', metaDescription);

    final keywords = product['searchKeywords'] is List
        ? (product['searchKeywords'] as List).map((e) => e.toString()).join(', ')
        : _text(product['keywords']);
    if (keywords.trim().isNotEmpty) {
      dom.setMetaByName('keywords', keywords);
    }

    dom.setMetaByProperty('og:title', metaTitle);
    dom.setMetaByProperty('og:description', metaDescription);
    dom.setMetaByProperty('og:type', 'product');
    dom.setMetaByProperty('og:url', url);
    dom.setMetaByProperty('og:image', image);

    dom.setMetaByName('twitter:card', 'summary_large_image');
    dom.setMetaByName('twitter:title', metaTitle);
    dom.setMetaByName('twitter:description', metaDescription);
    dom.setMetaByName('twitter:image', image);

    dom.setCanonical(url);
    // No Product JSON-LD here: productSeo's HTML already carries the one
    // Product schema (offers, breadcrumb, supplier text removed); a second
    // one from the app would duplicate it with raw seller text.
  }
}
