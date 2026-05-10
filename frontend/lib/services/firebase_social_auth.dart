import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseSocialAuth {
  const FirebaseSocialAuth._();

  static Future<UserCredential> signInWithGoogle() {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile')
      ..setCustomParameters({'prompt': 'select_account'});

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
