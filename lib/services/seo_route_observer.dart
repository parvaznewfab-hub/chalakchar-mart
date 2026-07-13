import 'package:flutter/widgets.dart';

import 'web_seo_service.dart';

/// Watches the root [Navigator] and toggles the `robots` meta tag so that
/// private/user-specific routes (currently /login and /cart) are marked
/// noindex while the rest of the site stays indexable.
class SeoRouteObserver extends NavigatorObserver {
  static const Set<String> _noIndexRoutes = {'/login', '/cart'};

  void _applyForRoute(Route<dynamic>? route) {
    final name = route?.settings.name;
    WebSeoService.setRobots(
      name != null && _noIndexRoutes.contains(name)
          ? 'noindex, nofollow'
          : 'index, follow',
    );
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
