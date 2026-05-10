import 'package:flutter/material.dart';

import 'auth/auth_gate.dart';
import 'firebase_options.dart';
import 'theme/kang_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseState = await FirebaseBootstrap.initialize();
  runApp(KangApp(firebaseState: firebaseState));
}

class KangApp extends StatelessWidget {
  const KangApp({super.key, required this.firebaseState});

  final FirebaseInitState firebaseState;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kang',
      theme: KangTheme.light(),
      home: AuthGate(firebaseState: firebaseState),
    );
  }
}
