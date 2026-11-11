import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'web_seo_dom.dart' as dom;

class WebSeoService {
  WebSeoService._();

  static const String siteName = 'ChalakChar Mart';
  static const String baseUrl = 'https://chalakcharmart.com';

  static String _text(dynamic value, [String fallback = '']) {
    final result = (value ?? '').toString().trim();
    return result.isEmpty ? fallback : result;
  }

  static double _toDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
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

    return '$baseUrl/icons/Icon-512.png';
  }

  static String _cleanDescription(String value) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 155) return clean;
    return '${clean.substring(0, 152).trim()}...';
  }

  /// Sets the `<meta name="robots">` tag content directly.
  ///
  /// Used to mark private/user-specific routes (e.g. /login, /cart) as
  /// noindex while leaving the rest of the site indexable.
  static void setRobots(String content) {
    if (!kIsWeb) return;
    dom.setMetaByName('robots', content);
  }

  static void setProductSeo({
    required Map<String, dynamic> product,
    required String productId,
    required double price,
    required int stock,
  }) {
    if (!kIsWeb) return;

    final productName = _text(product['name'], 'Product');
    final metaTitle = _text(
      product['metaTitle'],
      '$productName | Buy Online - $siteName',
    );

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
    final category = _text(product['category']);
    final brand = _text(product['brand'] ?? product['manufacturer'], siteName);
    final currency = 'BDT';
    final availability = stock > 0
        ? 'https://schema.org/InStock'
        : 'https://schema.org/OutOfStock';

    dom.setDocumentTitle(metaTitle);
    dom.setMetaByName('title', metaTitle);
    dom.setMetaByName('description', metaDescription);
    dom.setMetaByName('robots', 'index, follow');

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

    final schema = <String, dynamic>{
      '@context': 'https://schema.org',
      '@type': 'Product',
      'name': productName,
      'image': [image],
      'description': metaDescription,
      'sku': productId,
      'category': category,
      'brand': {
        '@type': 'Brand',
        'name': brand,
      },
      'offers': {
        '@type': 'Offer',
        'url': url,
        'priceCurrency': currency,
        'price': _toDouble(price).toStringAsFixed(2),
        'availability': availability,
        'itemCondition': 'https://schema.org/NewCondition',
        'seller': {
          '@type': 'Organization',
          'name': siteName,
        },
      },
    };

    final ratingCount = int.tryParse(_text(product['ratingCount'] ?? product['reviewCount'])) ?? 0;
    final ratingAvg = _toDouble(product['ratingAvg']);
    if (ratingCount > 0 && ratingAvg > 0) {
      schema['aggregateRating'] = {
        '@type': 'AggregateRating',
        'ratingValue': ratingAvg.toStringAsFixed(1),
        'reviewCount': ratingCount,
      };
    }

    dom.setJsonLd(
      'product-json-ld',
      const JsonEncoder.withIndent('  ').convert(schema),
    );
  }
}
