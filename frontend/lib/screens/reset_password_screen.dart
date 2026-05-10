import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _emailController.dispose();
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
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      setState(() => _success = '비밀번호 재설정 메일을 보냈습니다.');
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

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: '비밀번호 찾기',
      subtitle: '등록된 이메일로 재설정 링크를 보내드립니다.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.firebaseReady) ...[
              const AuthErrorText(message: 'Firebase 설정을 먼저 완료해 주세요.'),
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
            EmailField(
              controller: _emailController,
              textInputAction: TextInputAction.done,
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
                  : const Icon(Icons.mark_email_read_outlined),
              label: const Text('재설정 메일 보내기'),
              onPressed: _loading || !widget.firebaseReady ? null : _submit,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('로그인으로 돌아가기'),
              onPressed: _loading ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  String _firebaseMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
        return '가입된 이메일을 찾을 수 없습니다.';
      case 'invalid-email':
        return '올바른 이메일 형식이 아닙니다.';
      default:
        return error.message ?? '비밀번호 재설정 메일을 보낼 수 없습니다.';
    }
  }
}
