import 'package:kang_frontend/firebase_options.dart';
import 'package:kang_frontend/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows login screen when Firebase is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FamilyLoginApp(
        firebaseState: FirebaseInitState(ready: false, error: 'Firebase 설정 필요'),
      ),
    );

    expect(find.text('Kang 로그인'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('Firebase 설정 필요'), findsOneWidget);
  });
}
