import 'package:flutter/foundation.dart';

class AppConfig {
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _productionApiBaseUrl = 'https://kang.ai.kr';

  static String get apiBaseUrl {
    if (_apiBaseUrl.trim().isNotEmpty) {
      return _apiBaseUrl;
    }

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'http://localhost:8000';
      }
      return _productionApiBaseUrl;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        kReleaseMode ? _productionApiBaseUrl : 'http://10.0.2.2:8000',
      TargetPlatform.iOS || TargetPlatform.macOS =>
        kReleaseMode ? _productionApiBaseUrl : 'http://localhost:8000',
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => 'http://localhost:8000',
    };
  }
}
