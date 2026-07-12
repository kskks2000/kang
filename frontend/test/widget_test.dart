import 'package:flutter/foundation.dart';
import 'package:kang_frontend/app_config.dart';
import 'package:kang_frontend/firebase_options.dart';
import 'package:kang_frontend/main.dart';
import 'package:kang_frontend/services/toss_stock_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses production API host when API_BASE_URL is not provided', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(AppConfig.apiBaseUrl, 'https://www.kang.ai.kr');
  });

  test('parses available and locked holding quantities', () {
    final holding = TossHolding.fromJson({
      'symbol': 'KRW-USDT',
      'name': '테더',
      'marketCountry': 'UPBIT',
      'currency': 'KRW',
      'quantity': '5.75',
      'availableQuantity': '4.5',
      'lockedQuantity': '1.25',
      'lastPrice': '1500',
      'averagePurchasePrice': '1490',
      'marketValue': '8625',
      'profitLoss': '57.5',
      'profitLossRate': '0.67',
    });

    expect(holding.availableQuantity, '4.5');
    expect(holding.lockedQuantity, '1.25');

    final legacyHolding = TossHolding.fromJson({
      'symbol': '005930',
      'quantity': '3',
    });
    expect(legacyHolding.availableQuantity, '3');
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
