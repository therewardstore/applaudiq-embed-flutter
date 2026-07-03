import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'config.dart';
import 'internals.dart';

/// Renders the full Applaud IQ recognition portal in a hardened `webview_flutter` WebView with
/// auto / manual login + native SSO. Mirrors the web / iOS / Android / React Native SDK bridge
/// protocol and the same WebView confinement (origin-pinned navigation, origin-gated bridge,
/// origin-checked messages, HTTPS-only baseUrl, system-browser SSO).
///
/// ```dart
/// ApplaudIQEmbed(
///   config: EmbedConfig(key: 'pk_live_…', ssoCallback: 'myapp://sso-callback'),
///   token: embedToken,                 // auto mode — from your backend /embed/sessions
///   mode: ApplaudIQMode.auto,
///   onReady: () {}, onAuthPending: () {}, onError: (m) {}, onClose: () {}, onSignOut: () {},
/// )
/// ```
class ApplaudIQEmbed extends StatefulWidget {
  final EmbedConfig config;
  final String? token;
  final ApplaudIQMode mode;
  final VoidCallback? onReady;
  final VoidCallback? onClose;

  /// Bad/expired key or token, blocked load, OR a failed SSO sign-in.
  final void Function(String message)? onError;
  final VoidCallback? onAuthPending;

  /// The user signed out of an auto / host-managed embed — tear down your app's session.
  final VoidCallback? onSignOut;

  /// When true (default), the system back affordance (Android hardware Back / iOS edge-swipe)
  /// steps back through the embed's in-app history, popping the route only at the root.
  final bool backNavigation;

  const ApplaudIQEmbed({
    super.key,
    required this.config,
    this.token,
    this.mode = ApplaudIQMode.auto,
    this.onReady,
    this.onClose,
    this.onError,
    this.onAuthPending,
    this.onSignOut,
    this.backNavigation = true,
  });

  @override
  State<ApplaudIQEmbed> createState() => _ApplaudIQEmbedState();
}

class _ApplaudIQEmbedState extends State<ApplaudIQEmbed> {
  WebViewController? _controller;
  bool _readyFired = false;
  late final bool _secure;
  late final String _base;
  late final String? _baseOrigin;
  late final String _embedUrl;

  @override
  void initState() {
    super.initState();
    _base = widget.config.baseUrl.replaceAll(RegExp(r'/$'), '');
    _baseOrigin = originOf(_base);
    _embedUrl = buildEmbedUrl(_base, widget.mode.value, widget.config.key, token: widget.token);
    _secure = isSecureBaseUrl(_base, isDebug: kDebugMode);

    if (!_secure) {
      // Never load the WebView over a non-TLS portal — surface it and render nothing.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onError?.call('insecure_base_url'));
      return;
    }
    _controller = _buildController();
  }

  WebViewController _buildController() {
    // iOS: require a user gesture for media; inline playback. (Android equivalents set below.)
    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is WebKitWebViewPlatform
            ? WebKitWebViewControllerCreationParams(
                mediaTypesRequiringUserAction: const {
                  PlaybackMediaTypes.audio,
                  PlaybackMediaTypes.video,
                },
                allowsInlineMediaPlayback: true,
              )
            : const PlatformWebViewControllerCreationParams();

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('ApplaudIQFlutter', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Bridge is injected (origin-gated in the JS itself) as early as the high-level API allows.
          onPageStarted: (_) => unawaited(
            controllerSafe?.runJavaScript(injectedBridgeJs(widget.mode.value, _baseOrigin)) ??
                Future<void>.value(),
          ),
          onNavigationRequest: _onNavigation,
        ),
      )
      ..loadRequest(Uri.parse(_embedUrl));

    // Android lock-down (what the stable Dart API exposes): media needs a gesture; deny the file
    // chooser (no uploads from the embed). Mixed-content / file-URL access aren't surfaced by the
    // plugin — the portal is HTTPS-only and the nav guard + origin checks are the primary defenses.
    if (controller.platform is AndroidWebViewController) {
      final a = controller.platform as AndroidWebViewController;
      unawaited(a.setMediaPlaybackRequiresUserGesture(true));
      a.setOnShowFileSelector((_) async => const <String>[]);
    }
    return controller;
  }

  /// Null-safe accessor used inside the navigation-delegate closure during construction.
  WebViewController? get controllerSafe => _controller;

  // Pin the MAIN FRAME to the portal origin: off-origin top-level navigations open in the SYSTEM
  // browser (not in-WebView), so an open-redirect can't move the authenticated session + bridge onto
  // an attacker page. Sub-frames (reCAPTCHA, fonts, analytics) load in place.
  FutureOr<NavigationDecision> _onNavigation(NavigationRequest req) {
    if (!req.isMainFrame) return NavigationDecision.navigate;
    final url = req.url;
    if (url.startsWith('about:') || url.startsWith('data:') || sameOrigin(url, _base)) {
      return NavigationDecision.navigate;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
    }
    return NavigationDecision.prevent;
  }

  Future<void> _onMessage(JavaScriptMessage message) async {
    // Only the portal origin may drive the native bridge — a navigated-away / off-origin page (the
    // channel object is injected on every frame) must not spoof the handshake or trigger SSO.
    final current = await _controller?.currentUrl();
    if (!sameOrigin(current, _base)) return;

    Map<String, dynamic> d;
    try {
      d = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (d['source'] != 'applaudiq-embed') return;
    final payload = d['payload'] as Map<String, dynamic>?;

    switch (d['type']) {
      case 'applaudiq:ready':
      case 'applaudiq:authenticated':
        if (widget.mode == ApplaudIQMode.auto && (widget.token?.isNotEmpty ?? false)) {
          _sendToEmbed('applaudiq:init-token', {'token': widget.token});
        }
        if (!_readyFired) {
          _readyFired = true;
          widget.onReady?.call();
        }
        break;
      case 'applaudiq:auth-pending':
        widget.onAuthPending?.call();
        break;
      case 'applaudiq:error':
        widget.onError?.call((payload?['message'] ?? 'error').toString());
        break;
      case 'applaudiq:close':
        widget.onClose?.call();
        break;
      case 'applaudiq:signout':
        widget.onSignOut?.call();
        break;
      case 'applaudiq:sso-request':
        final raw = (payload?['provider'] ?? 'google').toString().toLowerCase();
        final provider = kSsoProviders.contains(raw) ? raw : 'google';
        final clientId = payload?['clientId']?.toString();
        final email = payload?['email']?.toString();
        unawaited(_openSSO(provider, clientId, email));
        break;
      case 'applaudiq:open-external':
        // Reward-store downloads / payment / OAuth: open the URL in the system browser.
        final url = payload?['url']?.toString() ?? '';
        if (url.startsWith('http://') || url.startsWith('https://')) {
          unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
        }
        break;
      case 'applaudiq:save-file':
        // Reward-store voucher download: the embed streamed the file bytes (base64) because a blob
        // download can't reach disk inside the WebView. Persist + open the OS share sheet.
        final base64Data = payload?['base64']?.toString() ?? '';
        final rawName = payload?['filename']?.toString() ?? 'download';
        final baseName = rawName.split(RegExp(r'[\\/]')).last; // basename only (no path traversal)
        final mime = payload?['mime']?.toString() ?? 'application/octet-stream';
        if (base64Data.isNotEmpty) {
          unawaited(
            _saveFile(base64Data, baseName.isEmpty ? 'download' : baseName, mime),
          );
        }
        break;
      case 'applaudiq:resize':
        break; // no-op on full-screen native
    }
  }

  /// Decode base64 file bytes → temp file → OS share sheet ("Save to Files" / share targets).
  /// Best-effort: any decode/write/share failure is swallowed so the host app never crashes.
  Future<void> _saveFile(String base64Data, String filename, String mime) async {
    try {
      final bytes = base64Decode(base64Data);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: mime, name: filename)]),
      );
    } catch (_) {
      // malformed base64 / write failed / user cancelled — best-effort.
    }
  }

  // SSO runs in the system browser (Google/Microsoft reject WebView OAuth). flutter_web_auth_2 opens
  // ASWebAuthenticationSession (iOS) / Custom Tabs (Android) and returns the callback URL.
  Future<void> _openSSO(String provider, String? clientId, String? email) async {
    final cb = widget.config.ssoCallback;
    final url = buildSsoUrl(_base, provider, clientId: clientId, email: email, nativeRedirect: cb);
    try {
      final result = await FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: schemeOf(cb));
      final code = callbackParam(result, 'code');
      if (code != null) {
        // Success: redeem the one-time code inside the WebView so cookies land in its store, reload.
        await _controller?.runJavaScript(completeSsoJs(code));
        return;
      }
      // Failure / identity-mismatch: surface it and reload the login so the user can retry.
      widget.onError?.call(callbackParam(result, 'error') ?? 'sso_failed');
      await _reloadLogin();
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return; // user dismissed the sheet — leave the login visible
      widget.onError?.call('sso_failed');
      await _reloadLogin();
    } catch (_) {
      widget.onError?.call('sso_failed');
      await _reloadLogin();
    }
  }

  Future<void> _reloadLogin() async => _controller?.loadRequest(Uri.parse(_embedUrl));

  void _sendToEmbed(String type, [Map<String, dynamic>? payload]) =>
      unawaited(_controller?.runJavaScript(sendToEmbedJs(type, payload)) ?? Future<void>.value());

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_secure || controller == null) return const SizedBox.shrink();
    final webView = WebViewWidget(controller: controller);
    if (!widget.backNavigation) return webView;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context); // capture before the async gap
        if (await controller.canGoBack()) {
          await controller.goBack();
        } else {
          navigator.maybePop();
        }
      },
      child: webView,
    );
  }
}
