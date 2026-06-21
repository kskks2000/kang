import 'package:flutter/foundation.dart';

class AppConfig {
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _productionApiBaseUrl = 'https://www.kang.ai.kr';

  static String get apiBaseUrl {
    if (_apiBaseUrl.trim().isNotEmpty) {
      return _apiBaseUrl;
    }

    if (kIsWeb) {
      return _productionApiBaseUrl;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _productionApiBaseUrl,
      TargetPlatform.iOS || TargetPlatform.macOS => _productionApiBaseUrl,
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => _productionApiBaseUrl,
    };
  }
}
