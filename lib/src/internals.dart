// Pure URL / origin / bridge-script helpers — no Flutter imports, fully unit-testable.
// Mirrors the iOS `EmbedInternals` / Android `EmbedInternals` / RN internals so the Flutter
// SDK builds the exact same embed + SSO URLs and runs the same bridge protocol.
import 'dart:convert';

/// Default portal origin when [EmbedConfig.baseUrl] is omitted.
const String kDefaultBase = 'https://recognize.applaudiq.com';

/// Providers the SDK will hand to the SSO authorize endpoint. Anything else falls back to google.
const List<String> kSsoProviders = ['google', 'microsoft'];

/// Normalizes a mode string to `auto` | `manual` (defaults to auto).
String normalizeMode(String? mode) => mode == 'manual' ? 'manual' : 'auto';

/// `<baseUrl>/embed?mode={auto|manual}&k={key}` (+ `&token=` in auto, + `&env=test` for `pk_test_` keys).
String buildEmbedUrl(String base, String mode, String key, {String? token}) {
  final m = normalizeMode(mode);
  final b = StringBuffer('$base/embed?mode=$m');
  if (key.isNotEmpty) b.write('&k=${Uri.encodeComponent(key)}');
  if (m == 'auto' && token != null && token.isNotEmpty) {
    b.write('&token=${Uri.encodeComponent(token)}');
  }
  if (key.startsWith('pk_test_')) b.write('&env=test');
  return b.toString();
}

/// `<baseUrl>/api/v1/auth/sso/{provider}/employee/authorize?native=1[&client_id=][&login_hint=][&native_redirect=]`.
String buildSsoUrl(
  String base,
  String provider, {
  String? clientId,
  String? email,
  String? nativeRedirect,
}) {
  final p = kSsoProviders.contains(provider.toLowerCase()) ? provider.toLowerCase() : 'google';
  final b = StringBuffer('$base/api/v1/auth/sso/$p/employee/authorize?native=1');
  if (clientId != null && clientId.isNotEmpty && clientId != 'null') {
    b.write('&client_id=${Uri.encodeComponent(clientId)}');
  }
  if (email != null && email.isNotEmpty) b.write('&login_hint=${Uri.encodeComponent(email)}');
  if (nativeRedirect != null && nativeRedirect.isNotEmpty) {
    b.write('&native_redirect=${Uri.encodeComponent(nativeRedirect)}');
  }
  return b.toString();
}

/// `scheme://host[:port]` for a URL, or null if it can't be parsed. Mirrors Android `originOf`.
String? originOf(String? url) {
  if (url == null || url.isEmpty) return null;
  final m = RegExp(r'^([a-z][a-z0-9.+-]*)://([^/?#]+)', caseSensitive: false).firstMatch(url);
  if (m == null) return null;
  return '${m.group(1)!.toLowerCase()}://${m.group(2)!.toLowerCase()}';
}

/// True when `a` and `b` share scheme+host(+port). Both must parse. Mirrors Android `sameOrigin`.
bool sameOrigin(String? a, String? b) {
  final oa = originOf(a);
  final ob = originOf(b);
  return oa != null && oa == ob;
}

/// The portal must be served over TLS. `http://` is allowed only for localhost-class hosts and only
/// when [isDebug] (the kDebugMode analogue — pass `kDebugMode` from the widget). Mirrors iOS
/// `isPortalURL` / Android `isSecureBaseUrl` / RN `isSecureBaseUrl`.
bool isSecureBaseUrl(String url, {required bool isDebug}) {
  final m = RegExp(r'^([a-z][a-z0-9.+-]*)://([^/?#:]+)', caseSensitive: false).firstMatch(url);
  if (m == null) return false;
  final scheme = m.group(1)!.toLowerCase();
  final host = m.group(2)!.toLowerCase();
  if (scheme == 'https') return true;
  final localhost = host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
  return scheme == 'http' && localhost && isDebug;
}

/// The scheme part of an `myapp://sso-callback` deep link — what `flutter_web_auth_2`'s
/// `callbackUrlScheme` expects (`myapp`). Falls back to `applaudiq` if unparseable.
String schemeOf(String? callback) {
  if (callback == null || callback.isEmpty) return 'applaudiq';
  final s = callback.split('://').first.trim();
  return s.isEmpty ? 'applaudiq' : s.toLowerCase();
}

/// True when `url` is THIS app's SSO callback (scheme+host match `callback`), regardless of query.
bool isSsoCallback(String? url, String? callback) {
  if (url == null || url.isEmpty || callback == null || callback.isEmpty) return false;
  return url.split('?').first == callback.split('?').first;
}

/// Pull a single decoded query param (`code` | `error`) from the callback deep link; null otherwise.
String? callbackParam(String url, String key) {
  final m = RegExp('[?&]$key=([^&]+)').firstMatch(url);
  if (m == null) return null;
  final raw = m.group(1);
  if (raw == null || raw.isEmpty) return null;
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}

/// Bridge installed at page start, ORIGIN-GATED to the portal origin only: forwards
/// `window.parent.postMessage` → the `ApplaudIQFlutter` channel and sets the native flag/mode the
/// portal reads (`isNativeEmbed` / `embedMode`). A navigated-to off-origin page never gets the bridge
/// or the flag. Mirrors iOS `forMainFrameOnly` + Android `onPageStarted` sameOrigin + RN origin gate.
String injectedBridgeJs(String mode, String? origin) {
  final m = normalizeMode(mode);
  final o = jsonEncode(origin ?? '');
  return '''
    if (window.location.origin === $o) {
      window.parent = window.parent || window;
      window.parent.postMessage = function(data){
        try { ApplaudIQFlutter.postMessage(JSON.stringify(data)); } catch(e){}
      };
      window.__APPLAUDIQ_EMBED__ = { mode: ${jsonEncode(m)}, native: true };
    }
    true;
  ''';
}

/// Redeem the one-time SSO code INSIDE the WebView (same-origin fetch) so the session cookies land in
/// the WebView's own store, then reload so the authenticated portal renders.
String completeSsoJs(String code) {
  return '''
    (async function(){
      try {
        const r = await fetch('/api/v1/employee/auth/sso/exchange', {
          method:'POST', credentials:'include',
          headers:{'Content-Type':'application/json'},
          body: JSON.stringify({ code: ${jsonEncode(code)} })
        });
        if (!r.ok) throw new Error('sso_exchange_failed');
        window.location.replace('/');
      } catch(e) {
        ApplaudIQFlutter.postMessage(JSON.stringify({
          source:'applaudiq-embed', type:'applaudiq:error', payload:{ message:'sso_exchange_failed' }
        }));
      }
    })(); true;
  ''';
}

/// Deliver an SDK→portal message as a `MessageEvent` on the page (matches the web/iOS/Android/RN
/// `sendToEmbed`). `code` is JSON-escaped, so it can't break out of the JS string.
String sendToEmbedJs(String type, [Map<String, dynamic>? payload]) {
  final msg = jsonEncode({'source': 'applaudiq-sdk', 'type': type, 'payload': payload});
  return "window.dispatchEvent(new MessageEvent('message',{data:${jsonEncode(msg)},origin:location.origin}));true;";
}
