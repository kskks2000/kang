import 'package:web/web.dart' as web;

class GoogleOAuthTokenStore {
  const GoogleOAuthTokenStore._();

  static String? read(String key) {
    try {
      final value = web.window.sessionStorage.getItem(key);
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static void write(String key, String value) {
    try {
      web.window.sessionStorage.setItem(key, value);
    } catch (_) {
      // Browsers can block storage in private or restricted contexts.
    }
  }

  static void remove(String key) {
    try {
      web.window.sessionStorage.removeItem(key);
    } catch (_) {
      // Browsers can block storage in private or restricted contexts.
    }
  }
}
