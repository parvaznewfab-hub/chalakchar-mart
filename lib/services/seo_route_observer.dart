import 'package:flutter/widgets.dart';

import 'web_seo_service.dart';

/// Watches the root [Navigator] and keeps page-level SEO tags in step with
/// client-side navigation: leaving a product page resets the product's
/// title, canonical link and JSON-LD, which the product page set for itself
/// (pages no longer reload between routes, so nothing else would clear them).
///
/// Robots are never written here: the server decides them for every URL
/// (functions/seo/, and firebase.json's X-Robots-Tag for /login and /cart).
class SeoRouteObserver extends NavigatorObserver {
  void _applyForRoute(Route<dynamic>? route) {
    // Only named (page) routes; dialogs and bottom sheets keep the page's tags.
    if (route is! PageRoute) return;
    final name = route.settings.name;
    final path = name == null ? null : Uri.tryParse(name)?.path;
    if (path != null && !path.startsWith('/product/')) {
      WebSeoService.resetPageSeo(path);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _applyForRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _applyForRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _applyForRoute(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _applyForRoute(previousRoute);
  }
}
