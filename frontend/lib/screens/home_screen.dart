import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/kang_theme.dart';
import '../widgets/kang_mark.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.userName;

    return Scaffold(
      appBar: AppBar(
        title: const KangMark(size: 36, showWordmark: true, compact: true),
        backgroundColor: KangColors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFCFAFF), Color(0xFFF0EAFE), Color(0xFFEAF9F5)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$displayName님, 환영합니다.',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user.email ?? 'Kang 계정',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 22),
                  const _WelcomePanel(),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      _HomeAction(
                        icon: Icons.calendar_month_outlined,
                        title: '캘린더',
                        status: '준비 중',
                      ),
                      _HomeAction(
                        icon: Icons.folder_copy_outlined,
                        title: '파일',
                        status: '준비 중',
                      ),
                      _HomeAction(
                        icon: Icons.contacts_outlined,
                        title: '연락처',
                        status: '준비 중',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                color: KangColors.mintSoft,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.verified_outlined,
                  color: KangColors.royalPurple,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '계정 준비가 완료되었습니다.',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kang의 주요 기능을 차분하게 연결해 나갈 수 있습니다.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeAction extends StatelessWidget {
  const _HomeAction({
    required this.icon,
    required this.title,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KangColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: KangColors.royalPurple),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(status, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
