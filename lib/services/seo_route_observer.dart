import 'package:flutter/widgets.dart';

import 'web_seo_service.dart';

/// Watches the root [Navigator] and keeps page-level SEO tags in step with
/// client-side navigation:
/// - private/user-specific routes (/login, /cart) are marked noindex while
///   the rest of the site stays indexable;
/// - leaving a product page resets the product's title, canonical link and
///   JSON-LD, which the product page set for itself (pages no longer reload
///   between routes, so nothing else would clear them).
class SeoRouteObserver extends NavigatorObserver {
  static const Set<String> _noIndexRoutes = {'/login', '/cart'};

  void _applyForRoute(Route<dynamic>? route) {
    // Only named (page) routes; dialogs and bottom sheets keep the page's tags.
    if (route is! PageRoute) return;
    final name = route.settings.name;
    final path = name == null ? null : Uri.tryParse(name)?.path;
    WebSeoService.setRobots(
      path != null && _noIndexRoutes.contains(path)
          ? 'noindex, nofollow'
          : 'index, follow',
    );
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
