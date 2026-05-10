import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseInitState {
  const FirebaseInitState({required this.ready, this.error});

  final bool ready;
  final String? error;
}

class FirebaseBootstrap {
  static Future<FirebaseInitState> initialize() async {
    if (!DefaultFirebaseOptions.isConfigured) {
      return const FirebaseInitState(
        ready: false,
        error: 'Firebase API 키와 프로젝트 ID가 필요합니다.',
      );
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return const FirebaseInitState(ready: true);
    } catch (error) {
      return FirebaseInitState(ready: false, error: error.toString());
    }
  }
}

class DefaultFirebaseOptions {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const webAppId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '1:153980946207:web:3044ef09ff07b6bf9f922a',
  );
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '153980946207',
  );
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  static bool get isConfigured => apiKey.isNotEmpty && projectId.isNotEmpty;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return _web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return FirebaseOptions(
          apiKey: apiKey,
          appId: androidAppId.isEmpty ? webAppId : androidAppId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
        );
      case TargetPlatform.iOS:
        return FirebaseOptions(
          apiKey: apiKey,
          appId: iosAppId.isEmpty ? webAppId : iosAppId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          iosBundleId: iosBundleId.isEmpty ? null : iosBundleId,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
        );
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return _web;
    }
  }

  static FirebaseOptions get _web {
    return FirebaseOptions(
      apiKey: apiKey,
      appId: webAppId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
    );
  }
}
