# Applaud IQ Embed SDK — Flutter

[![pub package](https://img.shields.io/pub/v/applaudiq_embed.svg)](https://pub.dev/packages/applaudiq_embed)

Embed the Applaud IQ recognition portal in a **Flutter** app (Android **and** iOS) with auto-login,
manual login, and native SSO. The SDK renders the portal in a hardened `webview_flutter` WebView and
mirrors the iOS / Android / React Native / Web SDK bridge protocol.

- **Auto + manual login** — silent sign-in with a server-minted token, or the portal's own email/SSO login.
- **Native SSO** — Google / Microsoft via the system browser, returned to your app on your own deep-link scheme.
- **Callbacks** — `onReady` / `onAuthPending` / `onError` / `onClose` / `onSignOut`.

---

## Build integration

### 1. Install

```sh
flutter pub add applaudiq_embed
cd ios && pod install && cd ..   # iOS only
```

### 2. Register your SSO callback scheme

SSO opens in the system browser and returns to your app via a deep link. Pick a scheme **unique to your
app** and register it natively; pass the same value as `config.ssoCallback` (`myapp://sso-callback`). The
SDK sends it to the backend as `native_redirect`, so the callback returns to *exactly* your app.

**iOS** — `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLSchemes</key>
  <array><string>myapp</string></array>
</dict></array>
```

**Android** — `android/app/src/main/AndroidManifest.xml`, inside `<application>` (the `CallbackActivity`
ships with `flutter_web_auth_2`):

```xml
<activity
    android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
    android:exported="true">
  <intent-filter android:label="flutter_web_auth_2">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="myapp" />
  </intent-filter>
</activity>
```

### 3. Import

```dart
import 'package:applaudiq_embed/applaudiq_embed.dart';
```

### 4. Mint a session on your server (auto-login)

For **auto-login**, your **backend** exchanges the secret for a one-time token (single-use, ~60s). Manual
login skips this entirely.

```
POST <your-api>/api/v1/embed/sessions
Authorization: Bearer aiq_embed_…          // the SECRET — server-side only
Content-Type: application/json

{ "employee": { "email": "employee@acme.com" }, "autoProvision": true }

// 200 OK → { "embedToken": "9f3a…", "expiresIn": 60, "hrPending": false }
```

### 5. Present the embed

```dart
ApplaudIQEmbed(
  config: EmbedConfig(
    key: 'pk_live_…',                       // publishable key from HR
    baseUrl: 'https://recognize.applaudiq.com',
    ssoCallback: 'myapp://sso-callback',    // your scheme from step 2
  ),
  token: embedToken,            // auto mode only — omit for manual
  mode: ApplaudIQMode.auto,     // .auto | .manual
  onReady: () {},
  onAuthPending: () {},         // signed in, awaiting HR approval
  onError: (msg) {},            // bad key/token OR a failed SSO sign-in
  onClose: () {},
  onSignOut: () {},             // user signed out of an auto embed
)
```

### SSO flow

Tapping **Continue with Google / Microsoft** opens the system browser (ASWebAuthenticationSession on iOS,
Custom Tabs on Android). On success the one-time code returns on `myapp://sso-callback?code=…` and is
exchanged inside the WebView (`onReady`). On failure (e.g. wrong account) the SDK fires `onError(message)`
and reloads the login so the user can retry.

---

## Security model

The SDK applies the same WebView hardening as the iOS and Android SDKs:

- **The WebView is pinned to the portal origin.** Only `baseUrl` loads in the main frame; off-origin
  top-level links open in the **system browser** instead (`url_launcher`), so an open-redirect can't move
  the authenticated session onto another page. Sub-frames (reCAPTCHA, fonts, analytics) still load in place.
- **The native bridge runs only on the portal origin.** The `postMessage` bridge and the
  `window.__APPLAUDIQ_EMBED__` flag install only when the page is the portal.
- **Only the portal can drive the bridge.** Every incoming message is checked against the WebView's current
  origin (`controller.currentUrl()`) before it is processed.
- **SSO runs in the system browser, not the WebView** — Google/Microsoft reject WebView OAuth; the one-time
  code is exchanged inside the WebView (cookies stay in its store).
- **The publishable key is browser-safe** — only the `pk_…` key lives in the app; the `aiq_embed_…` server
  secret must never be embedded (mint tokens on your backend).
- **`baseUrl` must use HTTPS** — a plain-`http://` base is rejected with `onError('insecure_base_url')` and
  nothing loads, except `localhost`/`127.0.0.1`/`10.0.2.2` in a debug build.

> **Platform note:** `webview_flutter`'s Dart API doesn't expose every native WebView setting. Mixed-content
> blocking and `file://`-URL access controls aren't surfaced by the plugin — the portal is HTTPS-only and the
> navigation guard + origin checks are the primary defenses; the SDK never loads `file://` content.

---

## Downloads & external links

When the portal (or the reward store nested inside it) needs to open a URL outside the WebView —
a file download, a payment page, or an OAuth handoff — it sends the `applaudiq:open-external` bridge
message with payload `{ url }`. The SDK opens `http(s)` URLs in the **system browser**
(`url_launcher`, `LaunchMode.externalApplication`). No app code is required.

---

## API

| Prop | Type | Notes |
|------|------|-------|
| `config.key` | `String` | Publishable `pk_…` key (required, both modes) |
| `config.baseUrl` | `String` | Portal origin; HTTPS in production |
| `config.ssoCallback` | `String?` | Your `myapp://sso-callback` deep link (required for SSO) |
| `token` | `String?` | One-time embed token (auto mode only) |
| `mode` | `ApplaudIQMode` | `.auto` \| `.manual` |
| `onReady` / `onAuthPending` / `onError` / `onClose` / `onSignOut` | callbacks | lifecycle |
| `backNavigation` | `bool` | system back steps through WebView history (default true) |

## Example

A runnable example app (one Flutter app, Android **and** iOS) lives in
[`applaudiq-sdk-example`](https://github.com/therewardstore/applaudiq-sdk-example/tree/master/native-integration/flutter)
under `native-integration/flutter/`.

## Changelog

Latest: **v1.2.0 (LTS)**. See [CHANGELOG.md](./CHANGELOG.md) for the full release history (also shown on the pub.dev page).
