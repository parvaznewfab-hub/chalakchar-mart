// No-op DOM helpers for non-web platforms (Android/iOS/desktop).

void setDocumentTitle(String title) {}

String getDocumentTitle() => '';

void setMetaByName(String name, String content) {}

void setMetaByProperty(String property, String content) {}

void setCanonical(String url) {}
