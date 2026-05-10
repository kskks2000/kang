import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firebase_social_auth.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';
import 'find_id_screen.dart';
import 'reset_password_screen.dart';
import 'sign_up_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.firebaseReady,
    this.firebaseError,
  });

  final bool firebaseReady;
  final String? firebaseError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.firebaseReady || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      setState(() => _error = _firebaseMessage(error));
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!widget.firebaseReady || _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      await FirebaseSocialAuth.signInWithGoogle();
    } on FirebaseAuthException catch (error) {
      setState(() => _error = FirebaseSocialAuth.googleErrorMessage(error));
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final configError = widget.firebaseReady ? null : widget.firebaseError;

    return AuthScaffold(
      title: '로그인',
      subtitle: '이메일과 비밀번호로 Kang에 로그인하세요.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (configError != null) ...[
              AuthErrorText(message: configError),
              const SizedBox(height: 16),
            ],
            if (_error != null) ...[
              AuthErrorText(message: _error!),
              const SizedBox(height: 16),
            ],
            if (_success != null) ...[
              AuthSuccessText(message: _success!),
              const SizedBox(height: 16),
            ],
            EmailField(controller: _emailController),
            const SizedBox(height: 12),
            PasswordField(
              controller: _passwordController,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.login),
              label: const Text('로그인'),
              onPressed: _loading || !widget.firebaseReady ? null : _submit,
            ),
            const SizedBox(height: 18),
            const AuthDivider(label: '또는 Google로 로그인'),
            const SizedBox(height: 18),
            GoogleAuthButton(
              label: 'Google로 로그인',
              loading: _loading,
              onPressed: widget.firebaseReady ? _signInWithGoogle : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('회원가입'),
              onPressed: _loading || !widget.firebaseReady ? null : _openSignUp,
            ),
            const Divider(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.manage_search),
                  label: const Text('ID 찾기'),
                  onPressed: _loading
                      ? null
                      : () => _open(const FindIdScreen()),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.password),
                  label: const Text('비밀번호 찾기'),
                  onPressed: _loading
                      ? null
                      : () => _open(
                          ResetPasswordScreen(
                            firebaseReady: widget.firebaseReady,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openSignUp() async {
    final result = await Navigator.of(context).push<SignUpResult>(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _error = null;
      _success = result.message;
    });
  }

  String _firebaseMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 올바르지 않습니다.';
      case 'too-many-requests':
        return '로그인 시도가 많습니다. 잠시 후 다시 시도해 주세요.';
      case 'user-disabled':
        return '사용 중지된 계정입니다.';
      default:
        return error.message ?? '로그인에 실패했습니다.';
    }
  }
}
