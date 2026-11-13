class WebUrlService {
  WebUrlService._();

  static void push(String path) {}
  static void replace(String path) {}
  static void pushInPage(String path) {}
  static Map<String, String> currentQuery() => const {};
  static void Function() onPopState(void Function(Map<String, String> query) onChange) =>
      () {};
}
