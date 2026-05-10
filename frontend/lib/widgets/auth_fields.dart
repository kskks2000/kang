import 'package:flutter/material.dart';

import '../theme/kang_theme.dart';

class EmailField extends StatelessWidget {
  const EmailField({
    super.key,
    required this.controller,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: textInputAction,
      decoration: const InputDecoration(
        labelText: '이메일 ID',
        prefixIcon: Icon(Icons.alternate_email),
      ),
      validator: (value) {
        final email = value?.trim() ?? '';
        if (email.isEmpty) {
          return '이메일을 입력해 주세요.';
        }
        if (!email.contains('@') || !email.contains('.')) {
          return '올바른 이메일 형식이 아닙니다.';
        }
        return null;
      },
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.labelText = '비밀번호',
    this.textInputAction = TextInputAction.done,
    this.onFieldSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final String labelText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: const [AutofillHints.password],
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      decoration: InputDecoration(
        labelText: widget.labelText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscure ? '비밀번호 보기' : '비밀번호 숨기기',
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator:
          widget.validator ??
          (value) {
            if ((value ?? '').isEmpty) {
              return '비밀번호를 입력해 주세요.';
            }
            return null;
          },
    );
  }
}

class AuthMessage extends StatelessWidget {
  const AuthMessage({
    super.key,
    required this.message,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final String message;
  final IconData icon;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthErrorText extends StatelessWidget {
  const AuthErrorText({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AuthMessage(
      message: message,
      icon: Icons.error_outline,
      foreground: const Color(0xFF9B1C1C),
      background: const Color(0xFFFFF1F1),
      border: const Color(0xFFFFCACA),
    );
  }
}

class AuthSuccessText extends StatelessWidget {
  const AuthSuccessText({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AuthMessage(
      message: message,
      icon: Icons.check_circle_outline,
      foreground: KangColors.royalPurple,
      background: KangColors.mintSoft,
      border: KangColors.mint.withValues(alpha: 0.45),
    );
  }
}
