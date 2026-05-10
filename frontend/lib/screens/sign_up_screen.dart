import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      await credential.user?.updateDisplayName(_nameController.text.trim());
      await credential.user?.sendEmailVerification();

      if (mounted) {
        Navigator.of(context).pop();
      }
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
      title: '가족 계정 만들기',
      subtitle: 'Kang에 초대된 이메일로 계정을 만듭니다.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              AuthErrorText(message: _error!),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: '이름',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return '이름을 입력해 주세요.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            EmailField(controller: _emailController),
            const SizedBox(height: 12),
            PasswordField(
              controller: _passwordController,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final password = value ?? '';
                if (password.length < 8) {
                  return '비밀번호는 8자 이상이어야 합니다.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirmPasswordController,
              labelText: '비밀번호 확인',
              validator: (value) {
                if (value != _passwordController.text) {
                  return '비밀번호가 서로 다릅니다.';
                }
                return null;
              },
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
                  : const Icon(Icons.person_add_alt_1),
              label: const Text('가입하기'),
              onPressed: _loading ? null : _submit,
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
      case 'email-already-in-use':
        return '이미 가입된 이메일입니다.';
      case 'invalid-email':
        return '올바른 이메일 형식이 아닙니다.';
      case 'weak-password':
        return '비밀번호가 너무 약합니다.';
      default:
        return error.message ?? '회원가입에 실패했습니다.';
    }
  }
}
