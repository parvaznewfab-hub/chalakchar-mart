// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void setDocumentTitle(String title) {
  html.document.title = title;
}

void setMetaByName(String name, String content) {
  final existing = html.document.head?.querySelector('meta[name="$name"]');
  final meta = existing is html.MetaElement
      ? existing
      : (html.MetaElement()..name = name);
  meta.content = content;
  if (existing is! html.MetaElement) html.document.head?.append(meta);
}

void setMetaByProperty(String property, String content) {
  final existing =
      html.document.head?.querySelector('meta[property="$property"]');
  final meta = existing is html.MetaElement ? existing : html.MetaElement();
  meta.setAttribute('property', property);
  meta.content = content;
  if (existing is! html.MetaElement) html.document.head?.append(meta);
}

void setCanonical(String url) {
  final existing = html.document.head?.querySelector('link[rel="canonical"]');
  final link = existing is html.LinkElement ? existing : html.LinkElement();
  link.rel = 'canonical';
  link.href = url;
  if (existing == null) html.document.head?.append(link);
}

void setJsonLd(String id, String json) {
  html.document.getElementById(id)?.remove();
  final script = html.ScriptElement()
    ..id = id
    ..type = 'application/ld+json'
    ..text = json;
  html.document.head?.append(script);
}
