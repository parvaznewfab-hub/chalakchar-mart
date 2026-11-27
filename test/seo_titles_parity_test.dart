import 'dart:io';

import 'package:chalakchar_mart/services/seo_titles.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app's page titles must match the server's first HTML, or the tab
/// title and meta tags change when Flutter starts. Reads the sources:
/// functions/seo/pages.js + html.js (pageSeo, POLICY_PAGE_SEO, limitText)
/// and web/index.html.
void main() {
  // Windows checkouts may have CRLF line ends.
  final js = [
    File('functions/seo/pages.js').readAsStringSync(),
    File('functions/seo/html.js').readAsStringSync(),
  ].join('\n').replaceAll('\r\n', '\n');
  final indexHtml = File('web/index.html').readAsStringSync().replaceAll('\r\n', '\n');

  test('lib/: the app never writes the robots meta (the server decides it)', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp(r'''setMetaByName\(\s*['"]robots['"]''').hasMatch(src) ||
          src.contains('setRobots(')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('lib/: the app adds no JSON-LD (the server sends the one Product schema)', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('application/ld+json') ||
          src.contains('setJsonLd') ||
          RegExp(r'''['"]@type['"]\s*:\s*['"]Product['"]''').hasMatch(src)) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  String decodeHtml(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  test('main.dart: MaterialApp title comes from WebSeoService.currentTitle', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('onGenerateTitle: (_) => WebSeoService.currentTitle'));
    expect(main, isNot(contains("title: 'ChalakChar Mart'")));
  });

  group('web/index.html', () {
    test('<title> == SeoTitles.homeTitle', () {
      final m = RegExp(r'<title>([^<]*)</title>').firstMatch(indexHtml);
      expect(m, isNotNull);
      expect(decodeHtml(m!.group(1)!), SeoTitles.homeTitle);
    });

    test('meta description == SeoTitles.homeDescription', () {
      final m = RegExp(r'<meta name="description" content="([^"]*)"').firstMatch(indexHtml);
      expect(m, isNotNull);
      expect(decodeHtml(m!.group(1)!), SeoTitles.homeDescription);
    });
  });

  group('functions/index.js POLICY_PAGE_SEO', () {
    final block = RegExp(r'const POLICY_PAGE_SEO = \{([\s\S]*?)\n\};').firstMatch(js);

    test('block found', () => expect(block, isNotNull));

    final entries = <String, SeoPageText>{};
    if (block != null) {
      final entry = RegExp(
        r'"(/[a-z-]+)":\s*\{\s*title:\s*"([^"]*)",\s*description:\s*"([^"]*)",?\s*\}',
      );
      for (final m in entry.allMatches(block.group(1)!)) {
        entries[m.group(1)!] = SeoPageText(title: m.group(2)!, description: m.group(3)!);
      }
    }

    test('same paths', () {
      expect(entries.keys.toSet(), SeoTitles.policyPages.keys.toSet());
    });

    for (final path in SeoTitles.policyPages.keys) {
      test('$path title and description', () {
        expect(entries[path]?.title, SeoTitles.policyPages[path]!.title);
        expect(entries[path]?.description, SeoTitles.policyPages[path]!.description);
      });
    }
  });

  group('functions/index.js pageSeo category', () {
    test('title pattern and limit', () {
      expect(js, contains(r'limitText(`${name} Price in Bangladesh | ChalakChar Mart`, 65)'));
      expect(SeoTitles.categoryTitle('Name'), 'Name Price in Bangladesh | ChalakChar Mart');
    });

    test('default description and limit', () {
      expect(
        js,
        contains(r'`ChalakChar Mart থেকে ${name} কিনুন — মডেল মিলিয়ে অর্ডার, ক্যাশ অন ডেলিভারি, সারা বাংলাদেশে হোম ডেলিভারি।`,' '\n    160'),
      );
      expect(
        SeoTitles.categoryDescription('Name'),
        'ChalakChar Mart থেকে Name কিনুন — মডেল মিলিয়ে অর্ডার, ক্যাশ অন ডেলিভারি, সারা বাংলাদেশে হোম ডেলিভারি।',
      );
    });

    test('not-found title and description', () {
      expect(js, contains('title: "${SeoTitles.notFoundTitle}"'));
      expect(js, contains('description: "${SeoTitles.notFoundDescription}"'));
    });

    test('limitText is the rule SeoTitles.limitText copies', () {
      expect(js, contains(r'const text = compactWhitespace(value);'));
      expect(js, contains(r'if (text.length <= max) return text;'));
      expect(js, contains(r'return `${text.slice(0, Math.max(0, max - 3)).trim()}...`;'));
    });
  });
}
