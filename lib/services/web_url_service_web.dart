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
    // Query included, so /category/x?sub=a → /category/x?sub=b still navigates.
    final current =
        '${html.window.location.pathname ?? '/'}${html.window.location.search ?? ''}';

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

  /// Changes the address bar to [path] (same page, e.g. a new ?sub=) and
  /// adds a back-button entry, without reloading. The current history
  /// state is copied so the entry still looks like Flutter's own.
  static void pushInPage(String path) {
    final normalized = _normalize(path);
    final location = html.window.location;
    if ('${location.pathname}${location.search}' == normalized) return;
    html.window.history.pushState(html.window.history.state, '', normalized);
  }

  /// Current address-bar query parameters.
  static Map<String, String> currentQuery() =>
      Uri.parse(html.window.location.href).queryParameters;

  /// Calls [onChange] with the new query parameters when back/forward moves
  /// between entries of the current path that differ only in the query
  /// (the ones [pushInPage] adds). Those events are consumed in the capture
  /// phase: Flutter's history handler would otherwise push a fresh copy of
  /// the initial route on top of the page. Any other back/forward is left
  /// to Flutter. Returns a function that removes the listener.
  static void Function() onPopState(void Function(Map<String, String> query) onChange) {
    final pagePath = html.window.location.pathname;
    void listener(html.Event event) {
      if (html.window.location.pathname != pagePath) return;
      event.stopImmediatePropagation();
      onChange(currentQuery());
    }

    html.window.addEventListener('popstate', listener, true);
    return () => html.window.removeEventListener('popstate', listener, true);
  }
}
