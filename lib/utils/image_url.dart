import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Hosts that legitimately serve plain http during local development
/// (Firebase emulators, Android emulator loopback). Never upgraded to https.
const Set<String> _localHttpHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

/// `<base>.jpg_<anything>.avif` / `<base>.jpg_.webp` → captures `<base>.jpg`.
/// AliExpress appends these transcoding suffixes; Flutter's mobile decoders
/// cannot decode AVIF, so we fall back to the original JPEG/PNG.
final RegExp _alicdnTranscodeSuffix = RegExp(
  r'^(.*?\.(?:jpe?g|png|gif))_[^/]*\.(?:avif|webp)$',
  caseSensitive: false,
);

/// Normalizes a product image URL so it can be loaded by `Image.network`
/// on every platform. Returns `''` for null/blank input.
String normalizeImageUrl(String? url) {
  var out = (url ?? '').trim();
  if (out.isEmpty) return '';

  if (out.startsWith('//')) {
    out = 'https:$out';
  } else if (out.toLowerCase().startsWith('http://')) {
    final rest = out.substring('http://'.length);
    final host = rest.split(RegExp(r'[/:?#]')).first.toLowerCase();
    if (!_localHttpHosts.contains(host)) out = 'https://$rest';
  }

  if (out.contains(' ')) out = out.replaceAll(' ', '%20');

  final host = Uri.tryParse(out)?.host.toLowerCase() ?? '';
  if (host == 'alicdn.com' || host.endsWith('.alicdn.com')) {
    // Only rewrite the path; keep any query string / fragment as-is.
    final cut = out.indexOf(RegExp(r'[?#]'));
    final path = cut == -1 ? out : out.substring(0, cut);
    final tail = cut == -1 ? '' : out.substring(cut);
    final match = _alicdnTranscodeSuffix.firstMatch(path);
    if (match != null) out = '${match.group(1)}$tail';
  }

  return out;
}

/// Square sizes the AliExpress CDN serves resized (`<img>_480x480q75.jpg_.webp`).
const List<int> _alicdnSizes = [120, 220, 350, 480, 640, 800, 960];

final RegExp _alicdnResizable = RegExp(r'\.(?:jpe?g|png)$', caseSensitive: false);

/// [normalizeImageUrl], and for AliExpress CDN images a resized WebP copy at
/// least [px] pixels on its longer side (e.g. a 200 KB product photo becomes
/// ~16 KB at 480). Other hosts (Firebase Storage) are returned unchanged.
/// Use the original URL where full resolution matters (zoom, full screen).
String sizedImageUrl(String? url, int px) {
  final out = normalizeImageUrl(url);
  if (out.isEmpty) return out;
  final uri = Uri.tryParse(out);
  final host = uri?.host.toLowerCase() ?? '';
  if (host != 'alicdn.com' && !host.endsWith('.alicdn.com')) return out;
  if (uri!.hasQuery || uri.hasFragment) return out;
  if (!_alicdnResizable.hasMatch(uri.path)) return out;
  final size = _alicdnSizes.firstWhere((s) => s >= px, orElse: () => _alicdnSizes.last);
  return '${out}_${size}x${size}q75.jpg_.webp';
}

final Set<String> _loggedImageFailures = <String>{};

/// Wraps an `Image.network` errorBuilder so failures are logged (debug builds
/// only, once per URL) with both the original and normalized URL, then shows
/// the caller's existing placeholder.
ImageErrorWidgetBuilder logImageError(
  String? originalUrl,
  ImageErrorWidgetBuilder placeholder,
) {
  return (context, error, stackTrace) {
    if (kDebugMode && _loggedImageFailures.add(originalUrl ?? '')) {
      debugPrint(
        '[image] load failed: $error\n'
        '  original:   $originalUrl\n'
        '  normalized: ${normalizeImageUrl(originalUrl)}',
      );
    }
    return placeholder(context, error, stackTrace);
  };
}
