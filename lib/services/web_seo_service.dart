// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

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

  static html.MetaElement _metaByName(String name) {
    final existing = html.document.head?.querySelector('meta[name="$name"]');
    if (existing is html.MetaElement) return existing;

    final meta = html.MetaElement()..name = name;
    html.document.head?.append(meta);
    return meta;
  }

  static html.MetaElement _metaByProperty(String property) {
    final existing = html.document.head?.querySelector('meta[property="$property"]');
    if (existing is html.MetaElement) return existing;

    final meta = html.MetaElement();
    meta.setAttribute('property', property);
    html.document.head?.append(meta);
    return meta;
  }

  static void _setCanonical(String url) {
    final existing = html.document.head?.querySelector('link[rel="canonical"]');
    final link = existing is html.LinkElement ? existing : html.LinkElement();
    link.rel = 'canonical';
    link.href = url;
    if (existing == null) html.document.head?.append(link);
  }

  static void _setJsonLd(Map<String, dynamic> schema) {
    html.document.getElementById('product-json-ld')?.remove();

    final script = html.ScriptElement()
      ..id = 'product-json-ld'
      ..type = 'application/ld+json'
      ..text = const JsonEncoder.withIndent('  ').convert(schema);

    html.document.head?.append(script);
  }

  /// Sets the `<meta name="robots">` tag content directly.
  ///
  /// Used to mark private/user-specific routes (e.g. /login, /cart) as
  /// noindex while leaving the rest of the site indexable.
  static void setRobots(String content) {
    if (!kIsWeb) return;
    _metaByName('robots').content = content;
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

    html.document.title = metaTitle;
    _metaByName('title').content = metaTitle;
    _metaByName('description').content = metaDescription;
    _metaByName('robots').content = 'index, follow';

    final keywords = product['searchKeywords'] is List
        ? (product['searchKeywords'] as List).map((e) => e.toString()).join(', ')
        : _text(product['keywords']);
    if (keywords.trim().isNotEmpty) {
      _metaByName('keywords').content = keywords;
    }

    _metaByProperty('og:title').content = metaTitle;
    _metaByProperty('og:description').content = metaDescription;
    _metaByProperty('og:type').content = 'product';
    _metaByProperty('og:url').content = url;
    _metaByProperty('og:image').content = image;

    _metaByName('twitter:card').content = 'summary_large_image';
    _metaByName('twitter:title').content = metaTitle;
    _metaByName('twitter:description').content = metaDescription;
    _metaByName('twitter:image').content = image;

    _setCanonical(url);

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

    _setJsonLd(schema);
  }
}
