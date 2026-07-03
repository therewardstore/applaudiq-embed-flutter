# Changelog

All notable changes to `applaudiq_embed` are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## 1.3.0

**Reward-store voucher download.** Adds the `applaudiq:save-file` bridge message (payload
`{ base64, filename, mime }`): the embedded reward store streams gift-card voucher bytes when a blob
download can't reach disk in a WebView. The SDK writes a temp file and opens the OS share sheet via
`share_plus` (adds `path_provider` + `share_plus` dependencies). Backward-compatible.

## 1.2.0

**Reward-store downloads / external links.** The SDK now handles the `applaudiq:open-external` bridge message
(payload `{ url }`) and opens the URL in the device's system browser — used by the embedded portal for file
downloads, payment pages, and OAuth handoffs. Backward-compatible; no changes to the public API surface.

## 1.1.1

**Long-Term Support (LTS) release.** Unified 1.1.1 across the Applaud IQ embed SDK family (Web · iOS · Android ·
React Native · Flutter). Maintenance / version-alignment release — **no public API changes** since 1.1.0.

## 1.1.0

**Long-Term Support (LTS) release.** Unified 1.1.0 across the SDK family (Web · iOS · Android · React Native ·
Flutter) — documentation & packaging refresh (README example link, a Changelog section; maintainer-only files
removed from the public repo). No public API changes.

## 1.0.0

First published release — full parity with the iOS, Android, and React Native SDKs, for **Android and iOS**.

- **Auto + manual login** in a `webview_flutter` WebView, mirroring the web/iOS/Android/RN bridge protocol
  (embed URL carries `mode`/`k`/`token`; `window.__APPLAUDIQ_EMBED__` injected on the portal origin).
- **Native SSO, end to end** — `applaudiq:sso-request` opens the system browser via `flutter_web_auth_2`
  (`…/auth/sso/{provider}/employee/authorize?native=1&client_id=&login_hint=&native_redirect=…`, provider
  allowlisted to google/microsoft); the one-time code returns on your app's `EmbedConfig.ssoCallback` deep
  link and is **exchanged inside the WebView**, then the portal reloads. On failure the SDK fires `onError`
  and reloads the login.
- **Per-app callback scheme** via `EmbedConfig.ssoCallback` so two Applaud IQ apps never collide on the callback.
- **Callbacks:** `onReady` / `onAuthPending` / `onError` / `onClose` / `onSignOut`; `backNavigation`.
- **Security (WebView hardening at iOS/Android parity):**
  - Main frame **pinned to the portal origin** — off-origin top-level navigations open in the system browser
    (`NavigationDelegate.onNavigationRequest` + `isMainFrame`).
  - The native bridge + `window.__APPLAUDIQ_EMBED__` flag are **origin-gated** — installed only on the portal.
  - Incoming bridge messages are **origin-checked** (`controller.currentUrl()`) before being processed.
  - Plain-`http://` `baseUrl` is **rejected** with `onError('insecure_base_url')` (localhost allowed only in debug).
  - WebView lock-down: media requires a user gesture; file chooser denied. (Mixed-content / `file://`-URL
    controls aren't exposed by `webview_flutter` — documented limitation; the portal is HTTPS-only.)
