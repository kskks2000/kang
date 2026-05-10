import 'package:flutter/foundation.dart';
import 'package:kang_frontend/app_config.dart';
import 'package:kang_frontend/firebase_options.dart';
import 'package:kang_frontend/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses Android emulator host when API_BASE_URL is not provided', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(AppConfig.apiBaseUrl, 'http://10.0.2.2:8000');
  });

  testWidgets('shows login screen when Firebase is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      const KangApp(
        firebaseState: FirebaseInitState(ready: false, error: 'Firebase 설정 필요'),
      ),
    );

    expect(find.text('이메일과 비밀번호로 Kang에 로그인하세요.'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
    expect(find.text('Firebase 설정 필요'), findsOneWidget);
  });
}
