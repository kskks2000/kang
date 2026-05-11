import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseSocialAuth {
  const FirebaseSocialAuth._();

  static const calendarEventsScope =
      'https://www.googleapis.com/auth/calendar.events';
  static const calendarEventsReadonlyScope =
      'https://www.googleapis.com/auth/calendar.events.readonly';

  static Future<UserCredential> signInWithGoogle() {
    final provider = _googleProvider();

    if (kIsWeb) {
      return FirebaseAuth.instance.signInWithPopup(provider);
    }
    return FirebaseAuth.instance.signInWithProvider(provider);
  }

  static Future<String> requestGoogleCalendarAccessToken() async {
    final provider = _googleProvider(
      scopes: const [calendarEventsScope],
      promptConsent: true,
    );
    final currentUser = FirebaseAuth.instance.currentUser;
    final credential = currentUser == null
        ? await _signInWithProvider(provider)
        : await currentUser.reauthenticateWithProvider(provider);
    final accessToken = credential.credential?.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-google-access-token',
        message: 'Google Calendar access token was not returned.',
      );
    }

    return accessToken;
  }

  static GoogleAuthProvider _googleProvider({
    List<String> scopes = const [],
    bool promptConsent = false,
  }) {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');

    for (final scope in scopes) {
      provider.addScope(scope);
    }

    provider.setCustomParameters({
      'prompt': promptConsent ? 'consent select_account' : 'select_account',
    });

    return provider;
  }

  static Future<UserCredential> _signInWithProvider(
    GoogleAuthProvider provider,
  ) {
    if (kIsWeb) {
      return FirebaseAuth.instance.signInWithPopup(provider);
    }
    return FirebaseAuth.instance.signInWithProvider(provider);
  }

  static String googleErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'popup-closed-by-user':
      case 'web-context-cancelled':
      case 'cancelled-popup-request':
        return 'Google 로그인이 취소되었습니다.';
      case 'account-exists-with-different-credential':
        return '같은 이메일로 다른 로그인 방식이 이미 연결되어 있습니다.';
      case 'operation-not-allowed':
        return 'Firebase 콘솔에서 Google 로그인 제공업체를 활성화해야 합니다.';
      case 'unauthorized-domain':
        final host = Uri.base.host;
        if (host.isEmpty) {
          return 'Firebase 인증 허용 도메인에 현재 사이트 주소를 추가해야 합니다.';
        }
        return 'Firebase 인증 허용 도메인에 $host를 추가해야 합니다.';
      case 'network-request-failed':
        return '네트워크 연결을 확인한 뒤 다시 시도해 주세요.';
      default:
        return error.message ?? 'Google 로그인에 실패했습니다.';
    }
  }
}
