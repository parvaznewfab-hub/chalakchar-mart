/// Shared endpoint builder for this project's asia-south1 Cloud Functions
/// (v2, HTTPS-triggered).
///
/// Uses the `*.cloudfunctions.net` alias host, matching the pattern already
/// proven in production by `aiProductFromImage` / `aiGenerateProductImage`
/// (see ai_product_optimizer_service.dart) — not the raw Cloud Run
/// `*.a.run.app` URL that `firebase deploy` prints, which points at the same
/// endpoint but is a different-format alias.
class CloudFunctionsUrls {
  CloudFunctionsUrls._();

  static const String _base =
      'https://asia-south1-chalakchar-mart.cloudfunctions.net';

  static Uri of(String functionName) => Uri.parse('$_base/$functionName');
}
