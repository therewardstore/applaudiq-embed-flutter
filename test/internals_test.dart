import 'package:applaudiq_embed/src/internals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildEmbedUrl', () {
    test('manual mode, no token, no env', () {
      expect(
        buildEmbedUrl('https://recognize.applaudiq.com', 'manual', 'pk_live_abc'),
        'https://recognize.applaudiq.com/embed?mode=manual&k=pk_live_abc',
      );
    });
    test('auto mode appends token', () {
      expect(
        buildEmbedUrl('https://x.test', 'auto', 'pk_live_abc', token: 't0k'),
        'https://x.test/embed?mode=auto&k=pk_live_abc&token=t0k',
      );
    });
    test('manual mode ignores token', () {
      expect(
        buildEmbedUrl('https://x.test', 'manual', 'pk_live_abc', token: 't0k'),
        'https://x.test/embed?mode=manual&k=pk_live_abc',
      );
    });
    test('pk_test_ key adds env=test', () {
      expect(
        buildEmbedUrl('https://x.test', 'auto', 'pk_test_abc'),
        'https://x.test/embed?mode=auto&k=pk_test_abc&env=test',
      );
    });
    test('unknown mode falls back to auto', () {
      expect(buildEmbedUrl('https://x.test', 'weird', 'k'), 'https://x.test/embed?mode=auto&k=k');
    });
  });

  group('buildSsoUrl', () {
    test('google with all params', () {
      expect(
        buildSsoUrl('https://x.test', 'google',
            clientId: '100001', email: 'a@b.com', nativeRedirect: 'myapp://sso-callback'),
        'https://x.test/api/v1/auth/sso/google/employee/authorize?native=1'
            '&client_id=100001&login_hint=a%40b.com&native_redirect=myapp%3A%2F%2Fsso-callback',
      );
    });
    test('unknown provider falls back to google', () {
      expect(
        buildSsoUrl('https://x.test', 'github'),
        'https://x.test/api/v1/auth/sso/google/employee/authorize?native=1',
      );
    });
    test('microsoft is allowed; "null" clientId + empty email skipped', () {
      expect(
        buildSsoUrl('https://x.test', 'microsoft', clientId: 'null', email: ''),
        'https://x.test/api/v1/auth/sso/microsoft/employee/authorize?native=1',
      );
    });
  });

  group('isSecureBaseUrl', () {
    test('https always allowed', () {
      expect(isSecureBaseUrl('https://recognize.applaudiq.com', isDebug: false), isTrue);
    });
    test('http rejected in production', () {
      expect(isSecureBaseUrl('http://localhost:3017', isDebug: false), isFalse);
      expect(isSecureBaseUrl('http://attacker.com', isDebug: true), isFalse);
    });
    test('http localhost-class allowed only in debug', () {
      expect(isSecureBaseUrl('http://localhost:3017', isDebug: true), isTrue);
      expect(isSecureBaseUrl('http://127.0.0.1:3017', isDebug: true), isTrue);
      expect(isSecureBaseUrl('http://10.0.2.2:3017', isDebug: true), isTrue);
    });
    test('garbage rejected', () {
      expect(isSecureBaseUrl('not a url', isDebug: true), isFalse);
    });
  });

  group('originOf / sameOrigin', () {
    test('extracts scheme://host[:port]', () {
      expect(originOf('https://x.test:3017/embed?a=1'), 'https://x.test:3017');
      expect(originOf('bad'), isNull);
    });
    test('sameOrigin compares origins', () {
      expect(sameOrigin('https://x.test/a', 'https://x.test/b'), isTrue);
      expect(sameOrigin('https://x.test', 'https://y.test'), isFalse);
      expect(sameOrigin(null, 'https://x.test'), isFalse);
    });
  });

  group('schemeOf / isSsoCallback / callbackParam', () {
    test('schemeOf extracts the scheme', () {
      expect(schemeOf('myapp://sso-callback'), 'myapp');
      expect(schemeOf(null), 'applaudiq');
      expect(schemeOf(''), 'applaudiq');
    });
    test('isSsoCallback matches scheme+host before query', () {
      expect(isSsoCallback('myapp://sso-callback?code=x', 'myapp://sso-callback'), isTrue);
      expect(isSsoCallback('other://sso-callback?code=x', 'myapp://sso-callback'), isFalse);
    });
    test('callbackParam decodes code/error or returns null', () {
      expect(callbackParam('myapp://cb?code=abc123', 'code'), 'abc123');
      expect(callbackParam('myapp://cb?error=wrong%20account', 'error'), 'wrong account');
      expect(callbackParam('myapp://cb?code=abc', 'error'), isNull);
      expect(callbackParam('myapp://cb', 'code'), isNull);
    });
  });

  group('injectedBridgeJs', () {
    test('is origin-gated and sets the native flag', () {
      final js = injectedBridgeJs('auto', 'https://x.test');
      expect(js, contains('window.location.origin === "https://x.test"'));
      expect(js, contains('__APPLAUDIQ_EMBED__'));
      expect(js, contains('native: true'));
      expect(js, contains('mode: "auto"'));
    });
  });
}
