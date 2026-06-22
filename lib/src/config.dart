import 'internals.dart' show kDefaultBase;

/// Configuration for [ApplaudIQEmbed]. The publishable [key] is required in both login modes; the
/// [ssoCallback] deep-link scheme is required only if your tenant uses SSO.
class EmbedConfig {
  /// Publishable key (`pk_live_…` / `pk_test_…`) from HR → Settings → Embed SDK Keys. Browser-safe.
  final String key;

  /// Portal origin. Defaults to `https://recognize.applaudiq.com`. Must be HTTPS in production
  /// (plain `http://` is allowed only for localhost in a debug build).
  final String baseUrl;

  /// YOUR app's SSO callback deep link, e.g. `myapp://sso-callback`. Register the scheme natively
  /// (iOS `Info.plist` `CFBundleURLTypes` + the `flutter_web_auth_2` `CallbackActivity` on Android).
  /// The SDK sends it to the backend as `native_redirect`, so the SSO callback returns to exactly
  /// your app — no Android "Open with" chooser when two Applaud IQ apps are installed. Required for SSO.
  final String? ssoCallback;

  const EmbedConfig({required this.key, this.baseUrl = kDefaultBase, this.ssoCallback});
}

/// Login mode: [auto] (silent sign-in with a server-minted token) or [manual] (the portal's own login).
enum ApplaudIQMode {
  auto,
  manual;

  String get value => this == ApplaudIQMode.manual ? 'manual' : 'auto';
}
