// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:flutter/services.dart';

/// Address-bar helpers for web.
///
/// Page changes go through Flutter's Navigator (named routes carry their
/// path), never through `window.location`, which would reload the whole app.
class WebUrlService {
  WebUrlService._();

  static String _normalize(String path) {
    final clean = path.trim().isEmpty ? '/' : path.trim();
    return clean.startsWith('/') ? clean : '/$clean';
  }

  /// Changes the address bar to [path] on the same page (e.g. a new ?sub=)
  /// without reloading or adding a history entry. Goes through Flutter's
  /// own history handling so its browser-history bookkeeping stays intact.
  static void replaceInPage(String path) {
    final normalized = _normalize(path);
    final location = html.window.location;
    if ('${location.pathname}${location.search}' == normalized) return;
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(normalized),
      replace: true,
    );
  }

  /// Current address-bar query parameters.
  static Map<String, String> currentQuery() =>
      Uri.parse(html.window.location.href).queryParameters;
}
