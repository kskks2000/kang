import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../models/app_user.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_api.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.firebaseState});

  final FirebaseInitState firebaseState;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthApi _authApi = AuthApi();
  Future<AppUser>? _sessionFuture;
  String? _sessionUid;

  @override
  Widget build(BuildContext context) {
    if (!widget.firebaseState.ready) {
      return LoginScreen(
        firebaseReady: false,
        firebaseError: widget.firebaseState.error,
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final firebaseUser = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(message: '로그인 상태를 확인하고 있습니다.');
        }
        if (firebaseUser == null) {
          _sessionFuture = null;
          _sessionUid = null;
          return const LoginScreen(firebaseReady: true);
        }

        if (_sessionUid != firebaseUser.uid || _sessionFuture == null) {
          _sessionUid = firebaseUser.uid;
          _sessionFuture = _loadSession(firebaseUser);
        }

        return FutureBuilder<AppUser>(
          future: _sessionFuture,
          builder: (context, sessionSnapshot) {
            if (sessionSnapshot.connectionState != ConnectionState.done) {
              return const _LoadingScreen(message: '가족 계정 권한을 확인하고 있습니다.');
            }
            if (sessionSnapshot.hasError || !sessionSnapshot.hasData) {
              return _SessionErrorScreen(
                message: sessionSnapshot.error?.toString() ?? '로그인 확인에 실패했습니다.',
              );
            }
            return HomeScreen(user: sessionSnapshot.data!);
          },
        );
      },
    );
  }

  Future<AppUser> _loadSession(User user) async {
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const ApiException('Firebase 로그인 토큰이 비어 있습니다.');
    }
    return _authApi.createSession(token);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _SessionErrorScreen extends StatelessWidget {
  const _SessionErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, size: 44),
                const SizedBox(height: 16),
                Text(
                  '로그인할 수 없습니다.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('다시 로그인'),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
