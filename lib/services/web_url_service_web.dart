// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

class WebUrlService {
  WebUrlService._();

  static String _normalize(String path) {
    final clean = path.trim().isEmpty ? '/' : path.trim();
    return clean.startsWith('/') ? clean : '/$clean';
  }

  /// Flutter Navigator 1.0 sometimes changes the widget stack without keeping
  /// the browser address bar in sync on web. For SEO routes, we use a real web
  /// navigation so /category/{slug} and /product/{id} are visible in the URL.
  static void push(String path) {
    final normalized = _normalize(path);
    final current = html.window.location.pathname ?? '/';

    if (current == normalized) return;

    // Full browser navigation is intentional for SEO pages.
    // It guarantees address bar, reload/deep-link, crawler URL and sharing URL.
    html.window.location.assign(normalized);
  }

  static void replace(String path) {
    final normalized = _normalize(path);
    final current = html.window.location.pathname ?? '/';

    if (current == normalized) return;

    html.window.location.replace(normalized);
  }
}
