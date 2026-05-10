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
    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.userName;
    final modules = _homeModules();

    return Scaffold(
      appBar: AppBar(
        title: const KangMark(size: 36, showWordmark: true, compact: true),
        backgroundColor: KangColors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFCFAFF), Color(0xFFF2ECFE), Color(0xFFEAF9F5)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 720;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 18 : 32,
                  isCompact ? 36 : 54,
                  isCompact ? 18 : 32,
                  36,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeroHeader(
                          displayName: displayName,
                          email: user.email ?? 'Kang 계정',
                        ),
                        const SizedBox(height: 22),
                        const _ConnectionStatusPanel(),
                        const SizedBox(height: 18),
                        _ModuleGrid(modules: modules),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<_HomeModule> _homeModules() {
    return const [
      _HomeModule(
        title: '캘린더',
        subtitle: '일정과 알림',
        status: '연동 준비',
        icon: Icons.calendar_month_outlined,
        accent: Color(0xFF5B3FA3),
        surface: Color(0xFFF3EEFF),
        screenTitle: '캘린더',
        screenSubtitle: 'Google Calendar 연결 준비',
        screenIcon: Icons.calendar_month_outlined,
      ),
      _HomeModule(
        title: '파일',
        subtitle: 'Drive 문서함',
        status: '연동 준비',
        icon: Icons.folder_copy_outlined,
        accent: Color(0xFF2DB7A5),
        surface: Color(0xFFE9FBF6),
        screenTitle: '파일',
        screenSubtitle: 'Google Drive 연결 준비',
        screenIcon: Icons.folder_copy_outlined,
      ),
      _HomeModule(
        title: '연락처',
        subtitle: '사람과 그룹',
        status: '연동 준비',
        icon: Icons.contacts_outlined,
        accent: Color(0xFF5867D8),
        surface: Color(0xFFEEF0FF),
        screenTitle: '연락처',
        screenSubtitle: 'Google Contacts 연결 준비',
        screenIcon: Icons.contacts_outlined,
      ),
      _HomeModule(
        title: '이메일',
        subtitle: '메시지 관리',
        status: '예정',
        icon: Icons.alternate_email_rounded,
        accent: Color(0xFFB15C2E),
        surface: Color(0xFFFFF3EA),
        screenTitle: '이메일',
        screenSubtitle: '메일 연동 준비',
        screenIcon: Icons.alternate_email_rounded,
      ),
      _HomeModule(
        title: '기록',
        subtitle: '개인 데이터',
        status: '예정',
        icon: Icons.article_outlined,
        accent: Color(0xFF44626F),
        surface: Color(0xFFEFF8FA),
        screenTitle: '기록',
        screenSubtitle: '개인 기록 공간 준비',
        screenIcon: Icons.article_outlined,
      ),
      _HomeModule(
        title: '설정',
        subtitle: '계정과 연동',
        status: '준비됨',
        icon: Icons.tune_rounded,
        accent: Color(0xFF2B1844),
        surface: Color(0xFFF4F0F8),
        screenTitle: '설정',
        screenSubtitle: '계정 설정',
        screenIcon: Icons.tune_rounded,
      ),
    ];
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.displayName, required this.email});

  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: KangColors.mintDeep,
              ),
              SizedBox(width: 7),
              Text(
                'KANG PRIVATE HUB',
                style: TextStyle(
                  color: KangColors.royalPurple,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '$displayName님, 환영합니다.',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          email,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 15,
            color: KangColors.slate,
          ),
        ),
      ],
    );
  }
}

class _ConnectionStatusPanel extends StatelessWidget {
  const _ConnectionStatusPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: KangColors.mintSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                color: KangColors.royalPurple,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '계정 준비가 완료되었습니다.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '캘린더, 파일, 연락처를 차례대로 연결할 수 있습니다.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontSize: 13),
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

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({required this.modules});

  final List<_HomeModule> modules;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 3
            : width >= 580
            ? 3
            : 2;
        final spacing = width < 420 ? 10.0 : 12.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final module in modules)
              SizedBox(
                width: itemWidth,
                child: _ModuleTile(module: module),
              ),
          ],
        );
      },
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final _HomeModule module;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _FeatureScreen(module: module)),
        ),
        child: Ink(
          height: 124,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KangColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: module.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(module.icon, color: module.accent, size: 19),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: KangColors.slate.withValues(alpha: 0.64),
                    size: 18,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                module.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                module.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  color: KangColors.slate,
                ),
              ),
              const SizedBox(height: 8),
              _StatusPill(text: module.status, color: module.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FeatureScreen extends StatelessWidget {
  const _FeatureScreen({required this.module});

  final _HomeModule module;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(module.screenTitle),
        backgroundColor: KangColors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFCFAFF), Color(0xFFF4F0FE), Color(0xFFEAF9F5)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FeatureHero(module: module),
                    const SizedBox(height: 16),
                    _FeaturePanel(module: module),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureHero extends StatelessWidget {
  const _FeatureHero({required this.module});

  final _HomeModule module;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: module.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(module.screenIcon, color: module.accent, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.screenTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    module.screenSubtitle,
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

class _FeaturePanel extends StatelessWidget {
  const _FeaturePanel({required this.module});

  final _HomeModule module;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_done_outlined, color: module.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Google 연동 준비 상태',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ReadinessRow(
              icon: Icons.storage_outlined,
              label: 'DB 테이블',
              value: '준비 완료',
              color: module.accent,
            ),
            const SizedBox(height: 10),
            _ReadinessRow(
              icon: Icons.key_outlined,
              label: 'OAuth 연결',
              value: '다음 단계',
              color: module.accent,
            ),
            const SizedBox(height: 10),
            _ReadinessRow(
              icon: Icons.sync_rounded,
              label: '동기화',
              value: '대기 중',
              color: module.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: KangColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _HomeModule {
  const _HomeModule({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.accent,
    required this.surface,
    required this.screenTitle,
    required this.screenSubtitle,
    required this.screenIcon,
  });

  final String title;
  final String subtitle;
  final String status;
  final IconData icon;
  final Color accent;
  final Color surface;
  final String screenTitle;
  final String screenSubtitle;
  final IconData screenIcon;
}
