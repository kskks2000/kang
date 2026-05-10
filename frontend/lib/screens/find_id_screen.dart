import 'package:flutter/material.dart';

import '../models/find_login_id_result.dart';
import '../services/auth_api.dart';
import '../theme/kang_theme.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';

class FindIdScreen extends StatefulWidget {
  const FindIdScreen({super.key});

  @override
  State<FindIdScreen> createState() => _FindIdScreenState();
}

class _FindIdScreenState extends State<FindIdScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _authApi = AuthApi();

  bool _loading = false;
  String? _error;
  FindLoginIdResult? _result;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await _authApi.findLoginId(_emailController.text.trim());
      setState(() => _result = result);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
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
      title: 'ID 찾기',
      subtitle: '가입한 이메일 ID를 확인합니다.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              AuthErrorText(message: _error!),
              const SizedBox(height: 16),
            ],
            if (_result != null) ...[
              _FindResult(result: _result!),
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
                  : const Icon(Icons.manage_search),
              label: const Text('ID 확인'),
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
}

class _FindResult extends StatelessWidget {
  const _FindResult({required this.result});

  final FindLoginIdResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.found
        ? KangColors.royalPurple
        : const Color(0xFF73510A);
    final background = result.found
        ? KangColors.mintSoft
        : const Color(0xFFFFF6DF);
    final border = result.found
        ? KangColors.mint.withValues(alpha: 0.45)
        : const Color(0xFFE7CF8E);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.found ? Icons.check_circle_outline : Icons.info_outline,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.message, style: TextStyle(color: color)),
                if (result.maskedLoginId != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    result.maskedLoginId!,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
