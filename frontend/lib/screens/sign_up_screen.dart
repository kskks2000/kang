import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_api.dart';
import '../services/firebase_social_auth.dart';
import '../theme/kang_theme.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';

class SignUpResult {
  const SignUpResult(this.message);

  final String message;
}

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
  final _authApi = AuthApi();

  bool _loading = false;
  String? _error;
  _CompletionState? _completion;

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
      final user = credential.user;

      try {
        await user?.updateDisplayName(_nameController.text.trim());
        final token = await user?.getIdToken(true);
        if (token == null || token.isEmpty) {
          throw const ApiException('Firebase 로그인 토큰이 비어 있습니다.');
        }
        await _authApi.createSession(token);
      } catch (error) {
        await _rollbackFirebaseUser(user);
        rethrow;
      }

      await _sendVerificationEmail(user);
      await FirebaseAuth.instance.signOut();
      _showCompletion(
        title: '회원가입이 완료되었습니다.',
        message: '이제 로그인 화면에서 이메일과 비밀번호로 Kang을 시작할 수 있습니다.',
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        final recoveryMessage = await _completeExistingFirebaseAccount();
        if (recoveryMessage == null) {
          return;
        }
        if (mounted) {
          setState(() => _error = recoveryMessage);
        }
        return;
      }
      setState(() => _error = _firebaseMessage(error));
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted && _completion == null) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signUpWithGoogle() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final credential = await FirebaseSocialAuth.signInWithGoogle();
      final user = credential.user;
      if (user == null) {
        throw const ApiException('Google 계정을 확인할 수 없습니다.');
      }

      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw const ApiException('Firebase 로그인 토큰이 비어 있습니다.');
      }

      await _authApi.createSession(token);
      await FirebaseAuth.instance.signOut();
      _showCompletion(
        name: user.displayName ?? user.email ?? 'Kang 사용자',
        email: user.email ?? '',
        title: 'Google 계정 연결이 완료되었습니다.',
        message: '이제 로그인 화면에서 Google로 바로 로그인할 수 있습니다.',
      );
    } on FirebaseAuthException catch (error) {
      await FirebaseAuth.instance.signOut();
      setState(() => _error = FirebaseSocialAuth.googleErrorMessage(error));
    } on ApiException catch (error) {
      await FirebaseAuth.instance.signOut();
      setState(() => _error = error.message);
    } catch (error) {
      await FirebaseAuth.instance.signOut();
      setState(() => _error = error.toString());
    } finally {
      if (mounted && _completion == null) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String?> _completeExistingFirebaseAccount() async {
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = credential.user;
      if (user == null) {
        return 'Firebase 계정을 확인할 수 없습니다.';
      }

      final displayName = (user.displayName ?? '').trim();
      if (displayName.isEmpty) {
        await user.updateDisplayName(_nameController.text.trim());
      }

      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        return 'Firebase 로그인 토큰이 비어 있습니다.';
      }

      await _authApi.createSession(token);
      await FirebaseAuth.instance.signOut();
      _showCompletion(
        title: '계정 정보가 준비되었습니다.',
        message: '기존 Firebase 계정을 확인했고 Kang 사용자 정보도 연결했습니다.',
      );
      return null;
    } on FirebaseAuthException catch (error) {
      await FirebaseAuth.instance.signOut();
      if (error.code == 'wrong-password' ||
          error.code == 'invalid-credential' ||
          error.code == 'invalid-login-credentials') {
        return '이미 가입된 이메일입니다. 기존 비밀번호로 로그인하거나 비밀번호 찾기를 이용해 주세요.';
      }
      return _firebaseMessage(error);
    } on ApiException catch (error) {
      await FirebaseAuth.instance.signOut();
      return error.message;
    } catch (error) {
      await FirebaseAuth.instance.signOut();
      return error.toString();
    }
  }

  Future<void> _sendVerificationEmail(User? user) async {
    try {
      await user?.sendEmailVerification();
    } on FirebaseAuthException {
      // Verification email is helpful but should not block account creation.
    }
  }

  Future<void> _rollbackFirebaseUser(User? user) async {
    try {
      await user?.delete();
    } on FirebaseAuthException {
      await FirebaseAuth.instance.signOut();
    } finally {
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
      }
    }
  }

  void _showCompletion({
    String? name,
    String? email,
    required String title,
    required String message,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _error = null;
      _completion = _CompletionState(
        name: name ?? _nameController.text.trim(),
        email: email ?? _emailController.text.trim(),
        title: title,
        message: message,
      );
    });
  }

  void _goToLogin() {
    final completion = _completion;
    Navigator.of(
      context,
    ).pop(SignUpResult(completion?.title ?? '회원가입이 완료되었습니다. 로그인해 주세요.'));
  }

  @override
  Widget build(BuildContext context) {
    final completion = _completion;
    if (completion != null) {
      return AuthScaffold(
        title: '가입 완료',
        subtitle: 'Kang 계정이 준비되었습니다.',
        child: _SignUpCompletePanel(
          completion: completion,
          onLoginPressed: _goToLogin,
        ),
      );
    }

    return AuthScaffold(
      title: '회원가입',
      subtitle: 'Kang 계정을 만들고 안전하게 시작하세요.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SignUpHeader(),
            const SizedBox(height: 18),
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
              label: Text(_loading ? '계정 준비 중' : '계정 만들기'),
              onPressed: _loading ? null : _submit,
            ),
            const SizedBox(height: 18),
            const AuthDivider(label: '또는 Google로 가입'),
            const SizedBox(height: 18),
            GoogleAuthButton(
              label: 'Google로 가입하기',
              loading: _loading,
              onPressed: _signUpWithGoogle,
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
        return '이미 가입된 이메일입니다. 로그인하거나 비밀번호 찾기를 이용해 주세요.';
      case 'invalid-email':
        return '올바른 이메일 형식이 아닙니다.';
      case 'weak-password':
        return '비밀번호가 너무 약합니다.';
      default:
        return error.message ?? '회원가입에 실패했습니다.';
    }
  }
}

class _CompletionState {
  const _CompletionState({
    required this.name,
    required this.email,
    required this.title,
    required this.message,
  });

  final String name;
  final String email;
  final String title;
  final String message;
}

class _SignUpHeader extends StatelessWidget {
  const _SignUpHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            color: KangColors.mintSoft,
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              Icons.verified_user_outlined,
              color: KangColors.royalPurple,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '가입 완료 여부를 화면에서 바로 확인할 수 있습니다.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '계정 생성과 Kang 연결이 끝난 뒤 완료 화면을 보여드립니다.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignUpCompletePanel extends StatelessWidget {
  const _SignUpCompletePanel({
    required this.completion,
    required this.onLoginPressed,
  });

  final _CompletionState completion;
  final VoidCallback onLoginPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: KangColors.mintSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KangColors.mint.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: KangColors.mintDeep,
                  size: 38,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                completion.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                completion.message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KangColors.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _CompleteRow(
                  icon: Icons.person_outline,
                  label: '이름',
                  value: completion.name,
                ),
                const SizedBox(height: 12),
                _CompleteRow(
                  icon: Icons.alternate_email,
                  label: '로그인 이메일',
                  value: completion.email,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const AuthSuccessText(
          message: '보안을 위해 자동 로그인하지 않았습니다. 아래 버튼으로 로그인 화면으로 이동해 주세요.',
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          icon: const Icon(Icons.login),
          label: const Text('로그인하러 가기'),
          onPressed: onLoginPressed,
        ),
      ],
    );
  }
}

class _CompleteRow extends StatelessWidget {
  const _CompleteRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: KangColors.royalPurple, size: 20),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(
              color: KangColors.slate,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KangColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
