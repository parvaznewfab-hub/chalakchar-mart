/// Firebase Auth's authDomain for the web build, chosen from the page's host.
///
/// Popup sign-in (Google, Facebook) opens `https://<authDomain>/__/auth/handler`.
/// With the default chalakchar-mart.firebaseapp.com, shoppers whose network
/// can't reach firebaseapp.com got ERR_CONNECTION_CLOSED and the login never
/// finished. Firebase Hosting serves /__/auth/handler on every hosted address,
/// so the page's own host is used instead: same origin, nothing extra to reach.
///
/// Each host used here must also be
///  - in Firebase Auth -> Authorized domains (Hosting adds channels itself), and
///  - in the Web OAuth client's "Authorized redirect URIs" as
///    `https://<host>/__/auth/handler` (Google), and in the Meta app's
///    "Valid OAuth Redirect URIs" (Facebook).
library;

const String defaultAuthDomain = 'chalakchar-mart.firebaseapp.com';

const Set<String> _ownHosts = {
  'chalakcharmart.com',
  'www.chalakcharmart.com',
  'chalakchar-mart.web.app',
  'chalakchar-mart.firebaseapp.com',
};

/// Hosting preview channels: `chalakchar-mart--<channel>-<hash>.web.app`
final RegExp _channelHost = RegExp(r'^chalakchar-mart--[a-z0-9-]+\.web\.app$');

/// [host] is Uri.base.host. Unknown hosts (localhost, anything else) keep
/// the default, which is always registered.
String authDomainForHost(String host) {
  final h = host.trim().toLowerCase();
  if (_ownHosts.contains(h) || _channelHost.hasMatch(h)) return h;
  return defaultAuthDomain;
}
