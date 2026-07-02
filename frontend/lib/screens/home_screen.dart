import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/academy_info_basic_info.dart';
import '../data/careernet_university_major_offerings.dart';
import '../data/kess_university_major_stats.dart';
import '../models/app_user.dart';
import '../services/academy_info_api.dart';
import '../services/firebase_social_auth.dart';
import '../services/financial_market_api.dart';
import '../services/google_calendar_launcher.dart';
import '../services/google_calendar_service.dart';
import '../services/google_drive_api.dart';
import '../services/google_keep_service.dart';
import '../services/google_keep_launcher.dart';
import '../services/stock_favorites_store.dart';
import '../services/stock_market_api.dart';
import '../services/subway_api.dart';
import '../services/toss_stock_api.dart';
import '../theme/kang_theme.dart';
import '../widgets/kang_mark.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GoogleCalendarService _calendarService = GoogleCalendarService();
  late Future<GoogleCalendarPreview> _todayCalendarPreview;

  @override
  void initState() {
    super.initState();
    _todayCalendarPreview = _loadTodayCalendarPreview();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user.displayName?.trim().isNotEmpty == true
        ? widget.user.displayName!.trim()
        : widget.user.userName;
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
            onPressed: () {
              FirebaseSocialAuth.clearCachedGoogleCalendarAccessToken();
              FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _DashboardBackground()),
          SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 720;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 18 : 34,
                    isCompact ? 34 : 50,
                    isCompact ? 18 : 34,
                    40,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeroHeader(
                            displayName: displayName,
                            email: widget.user.email ?? 'Kang 계정',
                          ),
                          const SizedBox(height: 22),
                          const _ConnectionStatusPanel(),
                          const SizedBox(height: 18),
                          _ModuleGrid(
                            modules: modules,
                            calendarPreview: _todayCalendarPreview,
                            onCalendarPreviewRefresh:
                                _refreshTodayCalendarPreview,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_HomeModule> _homeModules() {
    return const [
      _HomeModule(
        kind: _HomeModuleKind.calendar,
        title: '캘린더',
        subtitle: '일정과 알림',
        status: '연동 완료',
        icon: Icons.calendar_month_outlined,
        accent: Color(0xFF5B3FA3),
        surface: Color(0xFFF3EEFF),
        screenTitle: '캘린더',
        screenSubtitle: 'Google Calendar 연동 완료',
        screenIcon: Icons.calendar_month_outlined,
      ),
      _HomeModule(
        title: '파일',
        subtitle: 'Drive 문서함',
        status: '연동 완료',
        kind: _HomeModuleKind.drive,
        icon: Icons.folder_copy_outlined,
        accent: Color(0xFF2DB7A5),
        surface: Color(0xFFE9FBF6),
        screenTitle: '파일',
        screenSubtitle: 'Google Drive 연동 완료',
        screenIcon: Icons.folder_copy_outlined,
      ),
      _HomeModule(
        title: '메모',
        subtitle: 'Google Keep',
        status: '연동 완료',
        icon: Icons.sticky_note_2_outlined,
        accent: Color(0xFFE6A700),
        surface: Color(0xFFFFF7D8),
        kind: _HomeModuleKind.keep,
        screenTitle: '메모',
        screenSubtitle: 'Google Keep 메모와 체크리스트',
        screenIcon: Icons.sticky_note_2_outlined,
      ),
      _HomeModule(
        title: '세계 시총',
        subtitle: '주식 TOP 100',
        status: '실시간',
        icon: Icons.trending_up_rounded,
        accent: Color(0xFF0F766E),
        surface: Color(0xFFE8FAF6),
        kind: _HomeModuleKind.marketCap,
        screenTitle: '세계 시총 TOP 100',
        screenSubtitle: '글로벌 상장사 시가총액 순위',
        screenIcon: Icons.trending_up_rounded,
      ),
      _HomeModule(
        title: '주식 거래',
        subtitle: '거래 대시보드',
        status: '실전',
        icon: Icons.show_chart_rounded,
        accent: Color(0xFF15213F),
        surface: Color(0xFFEFF4FF),
        kind: _HomeModuleKind.stockTrading,
        screenTitle: '주식 거래 대시보드',
        screenSubtitle: '실시간 시세, 주문, 체결 현황',
        screenIcon: Icons.show_chart_rounded,
      ),
      _HomeModule(
        title: '금융정보',
        subtitle: '금리·환율·선물',
        status: '실시간',
        icon: Icons.query_stats_rounded,
        accent: Color(0xFF334155),
        surface: Color(0xFFEFF6FF),
        kind: _HomeModuleKind.financial,
        screenTitle: '금융정보',
        screenSubtitle: '미국채 금리, 주요 환율, 미국 선물',
        screenIcon: Icons.query_stats_rounded,
      ),
      _HomeModule(
        title: '지하철 정보',
        subtitle: '실시간 도착·열차 위치',
        status: '실시간',
        icon: Icons.train_rounded,
        accent: Color(0xFF2563EB),
        surface: Color(0xFFEFF6FF),
        kind: _HomeModuleKind.subway,
        screenTitle: '지하철 정보',
        screenSubtitle: '서울 지하철 실시간 도착정보와 열차 위치',
        screenIcon: Icons.train_rounded,
      ),
      _HomeModule(
        title: '대학 정보',
        subtitle: '학과·기본정보',
        status: '데이터 연동',
        icon: Icons.school_outlined,
        accent: Color(0xFF5867D8),
        surface: Color(0xFFEEF0FF),
        kind: _HomeModuleKind.university,
        screenTitle: '대학 정보',
        screenSubtitle: '대학별 학과와 대학알리미 기본정보',
        screenIcon: Icons.school_outlined,
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

  Future<GoogleCalendarPreview> _loadTodayCalendarPreview() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _calendarService.loadEventsForDate(today, interactive: false);
  }

  void _refreshTodayCalendarPreview() {
    setState(() {
      _todayCalendarPreview = _loadTodayCalendarPreview();
    });
  }
}

class _DashboardBackground extends StatelessWidget {
  const _DashboardBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: const [
        ColoredBox(color: Color(0xFFFAFCFF)),
        Image(
          image: AssetImage('assets/images/dashboard_mz_bg.png'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x7CFFFFFF), Color(0x42FFFFFF), Color(0xA6FFFFFF)],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.07),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 7),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _HeroChip(
              icon: Icons.auto_awesome_rounded,
              text: 'KANG PRIVATE HUB',
              color: KangColors.mintDeep,
            ),
            _HeroChip(
              icon: Icons.bolt_rounded,
              text: 'LIVE SYNC',
              color: KangColors.royalPurple,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '$displayName님, 환영합니다.',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 32,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.76)),
            boxShadow: [
              BoxShadow(
                color: KangColors.deepPurple.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: KangColors.mintSoft.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: KangColors.mint.withValues(alpha: 0.22),
                    ),
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
                        'Google 연동이 활성화되었습니다.',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '캘린더, 파일, 메모를 Kang에서 바로 확인할 수 있습니다.',
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
        ),
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({
    required this.modules,
    required this.calendarPreview,
    required this.onCalendarPreviewRefresh,
  });

  final List<_HomeModule> modules;
  final Future<GoogleCalendarPreview> calendarPreview;
  final VoidCallback onCalendarPreviewRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 760
            ? 3
            : width >= 480
            ? 2
            : 1;
        final spacing = width < 420 ? 10.0 : 14.0;
        final tileExtent = width < 480 ? 154.0 : 166.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: modules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: tileExtent,
          ),
          itemBuilder: (context, index) {
            final module = modules[index];
            if (module.kind == _HomeModuleKind.calendar) {
              return _CalendarModuleTile(
                module: module,
                preview: calendarPreview,
                onRefresh: onCalendarPreviewRefresh,
              );
            }
            return _ModuleTile(module: module);
          },
        );
      },
    );
  }
}

class _ModuleCardSurface extends StatelessWidget {
  const _ModuleCardSurface({
    required this.module,
    required this.onTap,
    required this.child,
  });

  final _HomeModule module;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: module.accent.withValues(alpha: 0.10),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.72),
            blurRadius: 18,
            offset: const Offset(-8, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: Colors.white.withValues(alpha: 0.46),
            child: InkWell(
              onTap: onTap,
              child: Ink(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.84),
                      module.surface.withValues(alpha: 0.46),
                      Colors.white.withValues(alpha: 0.56),
                    ],
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleIconBadge extends StatelessWidget {
  const _ModuleIconBadge({required this.module});

  final _HomeModule module;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: module.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: module.accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: module.accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(module.icon, color: module.accent, size: 20),
    );
  }
}

class _ModuleArrowButton extends StatelessWidget {
  const _ModuleArrowButton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.76)),
      ),
      child: Icon(
        Icons.arrow_forward_rounded,
        color: color.withValues(alpha: 0.66),
        size: 17,
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final _HomeModule module;

  @override
  Widget build(BuildContext context) {
    return _ModuleCardSurface(
      module: module,
      onTap: () {
        _openModule(context);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ModuleIconBadge(module: module),
              const Spacer(),
              _ModuleArrowButton(color: module.accent),
            ],
          ),
          const Spacer(),
          Text(
            module.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
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
          const SizedBox(height: 9),
          _StatusPill(text: module.status, color: module.accent),
        ],
      ),
    );
  }

  Future<void> _openModule(BuildContext context) async {
    if (module.kind == _HomeModuleKind.stockTrading) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _StockTradingFullScreen(module: module),
        ),
      );
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _FeatureScreen(module: module)));
  }
}

class _CalendarModuleTile extends StatelessWidget {
  const _CalendarModuleTile({
    required this.module,
    required this.preview,
    required this.onRefresh,
  });

  final _HomeModule module;
  final Future<GoogleCalendarPreview> preview;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _ModuleCardSurface(
      module: module,
      onTap: () {
        _openCalendar(context);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ModuleIconBadge(module: module),
              const Spacer(),
              _ModuleArrowButton(color: module.accent),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            module.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '오늘 Google Calendar 일정',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              color: KangColors.slate,
            ),
          ),
          const SizedBox(height: 7),
          Expanded(
            child: FutureBuilder<GoogleCalendarPreview>(
              future: preview,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _CalendarHomeStatus(
                    color: module.accent,
                    pill: '확인 중',
                    message: '오늘 일정을 불러오고 있습니다.',
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return _CalendarHomeStatus(
                    color: module.accent,
                    pill: '연결 필요',
                    message: '캘린더 권한을 연결하면 일정이 표시됩니다.',
                  );
                }

                final events = snapshot.data!.events;
                if (events.isEmpty) {
                  return _CalendarHomeStatus(
                    color: module.accent,
                    pill: '오늘 0개',
                    message: '오늘 등록된 일정이 없습니다.',
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusPill(
                      text: '오늘 ${events.length}개',
                      color: module.accent,
                    ),
                    const SizedBox(height: 7),
                    for (final event in events.take(1))
                      _CalendarHomeEventLine(event: event),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCalendar(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _FeatureScreen(module: module)));
    onRefresh();
  }
}

class _CalendarHomeStatus extends StatelessWidget {
  const _CalendarHomeStatus({
    required this.color,
    required this.pill,
    required this.message,
  });

  final Color color;
  final String pill;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusPill(text: pill, color: color),
        const SizedBox(height: 5),
        Text(
          message,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: KangColors.slate,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _CalendarHomeEventLine extends StatelessWidget {
  const _CalendarHomeEventLine({required this.event});

  final GoogleCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Text(
            _timeText(event),
            style: const TextStyle(
              color: KangColors.royalPurple,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KangColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _timeText(GoogleCalendarEvent event) {
    if (event.allDay) {
      return '종일';
    }

    final start = event.start?.toLocal();
    if (start == null) {
      return '시간 없음';
    }

    return '${_two(start.hour)}:${_two(start.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.1)),
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
    if (module.kind == _HomeModuleKind.calendar) {
      return _CalendarFeaturePanel(module: module);
    }
    if (module.kind == _HomeModuleKind.drive) {
      return _DriveFeaturePanel(module: module);
    }
    if (module.kind == _HomeModuleKind.keep) {
      return _KeepFeaturePanel(module: module);
    }
    if (module.kind == _HomeModuleKind.university) {
      return _UniversityFeaturePanel(module: module);
    }
    if (module.kind == _HomeModuleKind.marketCap) {
      return _MarketCapFeaturePanel(module: module);
    }
    if (module.kind == _HomeModuleKind.financial) {
      return _FinancialInfoFeaturePanel(module: module);
    }
    if (module.kind == _HomeModuleKind.subway) {
      return _SubwayFeaturePanel(module: module);
    }
    if (module.kind == _HomeModuleKind.stockTrading) {
      return _StockTradingPlaceholderPanel(module: module);
    }

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
                    'Google 연동 상태',
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
              value: '연결 완료',
              color: module.accent,
            ),
            const SizedBox(height: 10),
            _ReadinessRow(
              icon: Icons.sync_rounded,
              label: '동기화',
              value: '활성화',
              color: module.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketCapFeaturePanel extends StatefulWidget {
  const _MarketCapFeaturePanel({required this.module});

  final _HomeModule module;

  @override
  State<_MarketCapFeaturePanel> createState() => _MarketCapFeaturePanelState();
}

class _MarketCapFeaturePanelState extends State<_MarketCapFeaturePanel> {
  final StockMarketApi _stockMarketApi = StockMarketApi();
  final TextEditingController _searchController = TextEditingController();
  late Future<MarketCapTopDataset> _future;

  String _activeSector = '전체';
  int _visibleCount = 30;

  @override
  void initState() {
    super.initState();
    _future = _stockMarketApi.loadGlobalTop();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = _stockMarketApi.loadGlobalTop();
      _visibleCount = 30;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.84)),
        boxShadow: [
          BoxShadow(
            color: widget.module.accent.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<MarketCapTopDataset>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final dataset = snapshot.data;
            final companies = dataset?.companies ?? const <MarketCapCompany>[];
            final sectors =
                [
                  '전체',
                  ...{
                    for (final company in companies)
                      if (company.sector.isNotEmpty) company.sector,
                  },
                ]..sort((a, b) {
                  if (a == '전체') {
                    return -1;
                  }
                  if (b == '전체') {
                    return 1;
                  }
                  return a.compareTo(b);
                });
            final activeSector = sectors.contains(_activeSector)
                ? _activeSector
                : '전체';
            final query = _searchController.text;
            final filtered = companies
                .where((company) => company.matches(query))
                .where(
                  (company) =>
                      activeSector == '전체' || company.sector == activeSector,
                )
                .toList(growable: false);
            final visible = filtered
                .take(_visibleCount)
                .toList(growable: false);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.trending_up_rounded,
                      color: widget.module.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '세계 시가총액 순위',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _StatusPill(
                      text: loading ? '조회 중' : '${companies.length}개',
                      color: widget.module.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading)
                  const _CalendarMessage(
                    icon: Icons.cloud_sync_outlined,
                    text: '세계 시총 TOP 100 데이터를 불러오고 있습니다.',
                    color: KangColors.slate,
                  )
                else if (snapshot.hasError || dataset == null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CalendarMessage(
                        icon: Icons.error_outline_rounded,
                        text:
                            snapshot.error?.toString() ??
                            '세계 시총 데이터를 불러오지 못했습니다.',
                        color: Colors.red,
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('다시 조회'),
                          onPressed: _refresh,
                        ),
                      ),
                    ],
                  )
                else ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _UniversitySummaryTile(
                        icon: Icons.format_list_numbered_rounded,
                        label: '리스트',
                        value: '${dataset.summary.count}개',
                        color: widget.module.accent,
                      ),
                      _UniversitySummaryTile(
                        icon: Icons.emoji_events_outlined,
                        label: '1위',
                        value: dataset.summary.topSymbol,
                        color: KangColors.royalPurple,
                      ),
                      _UniversitySummaryTile(
                        icon: Icons.paid_outlined,
                        label: '1위 시총',
                        value: _formatUsdCompact(dataset.summary.topMarketCap),
                        color: KangColors.mintDeep,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _UniversitySourceNote(
                    color: widget.module.accent,
                    title:
                        '${dataset.source.provider} · ${dataset.source.title}',
                    description:
                        '글로벌 상장사를 시가총액 기준으로 정렬한 정보성 데이터입니다. '
                        '마지막 원본 갱신: ${_formatMarketCapDate(dataset.summary.lastUpdated)}',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() => _visibleCount = 30),
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        Icons.manage_search_rounded,
                        color: widget.module.accent,
                      ),
                      labelText: '종목 검색',
                      hintText: '회사명, 티커, 국가, 섹터, 산업',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: KangColors.line.withValues(alpha: 0.92),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: widget.module.accent,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final sector in sectors)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(sector),
                              selected: activeSector == sector,
                              selectedColor: widget.module.accent.withValues(
                                alpha: 0.14,
                              ),
                              side: BorderSide(
                                color: activeSector == sector
                                    ? widget.module.accent.withValues(
                                        alpha: 0.28,
                                      )
                                    : KangColors.line,
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _activeSector = sector;
                                  _visibleCount = 30;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DriveRowsHeader(
                    count: filtered.length,
                    loading: false,
                    color: widget.module.accent,
                    title: '세계 시총 TOP 100',
                  ),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    const _CalendarMessage(
                      icon: Icons.search_off_rounded,
                      text: '조건에 맞는 종목이 없습니다.',
                      color: KangColors.slate,
                    )
                  else ...[
                    for (final company in visible)
                      _MarketCapCompanyTile(
                        company: company,
                        color: widget.module.accent,
                      ),
                    if (_visibleCount < filtered.length) ...[
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          '더 보기 (${filtered.length - _visibleCount}개 남음)',
                        ),
                        onPressed: () {
                          setState(() => _visibleCount += 25);
                        },
                      ),
                    ],
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StockTradingFullScreen extends StatefulWidget {
  const _StockTradingFullScreen({required this.module});

  final _HomeModule module;

  @override
  State<_StockTradingFullScreen> createState() =>
      _StockTradingFullScreenState();
}

enum _StockTradingWorkspace { watchlist, chart, orders, executions, strategy }

const _stockTradingAllWatchlistGroupId = '__all__';
const _stockTradingDefaultWatchlistGroupId = 'my-watchlist';
const _stockTradingDefaultWatchlistGroupName = 'My Watchlist';

class _StockTradingWatchlistGroup {
  const _StockTradingWatchlistGroup({
    required this.id,
    required this.name,
    required this.symbols,
  });

  final String id;
  final String name;
  final List<String> symbols;

  _StockTradingWatchlistGroup copyWith({
    String? id,
    String? name,
    List<String>? symbols,
  }) {
    return _StockTradingWatchlistGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      symbols: symbols ?? this.symbols,
    );
  }
}

class _StockTradingFullScreenState extends State<_StockTradingFullScreen> {
  final TossStockApi _tossStockApi = TossStockApi();
  final StockFavoritesStore _domesticLegacyWatchlistStore = StockFavoritesStore(
    'kang.stock.watchlist.kr',
  );
  final StockFavoritesStore _overseasLegacyWatchlistStore = StockFavoritesStore(
    'kang.stock.watchlist.us',
  );
  final StockFavoritesStore _domesticWatchlistGroupStore = StockFavoritesStore(
    'kang.stock.watchlist.groups.kr',
  );
  final StockFavoritesStore _overseasWatchlistGroupStore = StockFavoritesStore(
    'kang.stock.watchlist.groups.us',
  );

  var _selectedMarket = _StockTradingMarket.domestic;
  var _selectedInterval = _StockTradingChartInterval.day;
  var _activeWorkspace = _StockTradingWorkspace.watchlist;
  String? _selectedDomesticSymbol;
  String? _selectedOverseasSymbol;
  var _watchlistWorkspaceSplitRatio = 5 / 9;
  var _rightColumnSplitRatio = 5 / 8;
  double? _rightColumnWidth;
  TossStockDashboard? _dashboard;
  String? _dashboardError;
  final Map<String, TossStockQuote> _quoteCache = {};
  List<_StockTradingWatchlistGroup> _domesticWatchlistGroups =
      const <_StockTradingWatchlistGroup>[
        _StockTradingWatchlistGroup(
          id: _stockTradingDefaultWatchlistGroupId,
          name: _stockTradingDefaultWatchlistGroupName,
          symbols: <String>[],
        ),
      ];
  List<_StockTradingWatchlistGroup> _overseasWatchlistGroups =
      const <_StockTradingWatchlistGroup>[
        _StockTradingWatchlistGroup(
          id: _stockTradingDefaultWatchlistGroupId,
          name: _stockTradingDefaultWatchlistGroupName,
          symbols: <String>[],
        ),
      ];
  var _selectedDomesticWatchlistGroupId = _stockTradingDefaultWatchlistGroupId;
  var _selectedOverseasWatchlistGroupId = _stockTradingDefaultWatchlistGroupId;
  var _loadingDashboard = false;
  var _loadSerial = 0;

  _StockTradingMarketConfig get _config =>
      _StockTradingMarketConfig.byMarket(_selectedMarket);

  String get _marketCode =>
      _selectedMarket == _StockTradingMarket.domestic ? 'KR' : 'US';

  String get _activeSymbol => _selectedMarket == _StockTradingMarket.domestic
      ? _selectedDomesticSymbol ?? '005930'
      : _selectedOverseasSymbol ?? 'NVDA';

  List<_StockTradingWatchlistGroup> get _currentWatchlistGroups =>
      _selectedMarket == _StockTradingMarket.domestic
      ? _domesticWatchlistGroups
      : _overseasWatchlistGroups;

  String get _currentSelectedWatchlistGroupId {
    final groupId = _selectedMarket == _StockTradingMarket.domestic
        ? _selectedDomesticWatchlistGroupId
        : _selectedOverseasWatchlistGroupId;
    if (groupId == _stockTradingAllWatchlistGroupId ||
        _currentWatchlistGroups.any((group) => group.id == groupId)) {
      return groupId;
    }
    return _stockTradingDefaultWatchlistGroupId;
  }

  _StockTradingWatchlistGroup? get _currentSelectedWatchlistGroup {
    final groupId = _currentSelectedWatchlistGroupId;
    for (final group in _currentWatchlistGroups) {
      if (group.id == groupId) {
        return group;
      }
    }
    return null;
  }

  List<String> get _currentCustomWatchlistSymbols =>
      _flattenStockTradingWatchlistGroupSymbols(
        _currentWatchlistGroups,
        marketCode: _marketCode,
      );

  List<String> get _currentVisibleWatchlistSymbols {
    if (_currentSelectedWatchlistGroupId == _stockTradingAllWatchlistGroupId) {
      return _currentCustomWatchlistSymbols;
    }
    return _currentSelectedWatchlistGroup?.symbols ?? const <String>[];
  }

  String get _currentWatchlistAddTargetName {
    if (_currentSelectedWatchlistGroupId == _stockTradingAllWatchlistGroupId) {
      return _stockTradingDefaultWatchlistGroupName;
    }
    return _currentSelectedWatchlistGroup?.name ??
        _stockTradingDefaultWatchlistGroupName;
  }

  TossStockDashboard? get _currentMarketDashboard {
    final dashboard = _dashboard;
    if (dashboard == null) {
      return null;
    }
    return dashboard.summary.market.trim().toUpperCase() == _marketCode
        ? dashboard
        : null;
  }

  TossStockDashboard? get _activeDashboard {
    final dashboard = _currentMarketDashboard;
    if (dashboard == null) {
      return null;
    }
    return dashboard.summary.primarySymbol.trim().toUpperCase() == _activeSymbol
        ? dashboard
        : null;
  }

  List<TossStockQuote> get _currentMarketQuotes {
    final quotesBySymbol = <String, TossStockQuote>{};
    for (final entry in _quoteCache.entries) {
      final parts = entry.key.split(':');
      if (parts.length == 2 && parts.first == _marketCode) {
        quotesBySymbol[parts.last] = entry.value;
      }
    }
    for (final quote
        in _currentMarketDashboard?.watchlist ?? const <TossStockQuote>[]) {
      final symbol = quote.symbol.trim().toUpperCase();
      if (symbol.isNotEmpty) {
        quotesBySymbol[symbol] = quote;
      }
    }
    return quotesBySymbol.values.toList(growable: false);
  }

  TossStockQuote? get _activeQuote =>
      _stockQuoteForSymbol(_currentMarketQuotes, _activeSymbol);

  @override
  void initState() {
    super.initState();
    _loadStoredWatchlists();
    _loadDashboard();
  }

  @override
  void dispose() {
    _tossStockApi.close();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    final serial = ++_loadSerial;
    setState(() {
      _loadingDashboard = true;
      _dashboardError = null;
    });
    try {
      final dashboard = await _tossStockApi.loadDashboard(
        market: _marketCode,
        symbol: _activeSymbol,
        symbols: [_activeSymbol, ..._currentCustomWatchlistSymbols],
        candleInterval: _selectedInterval.sourceInterval,
      );
      if (!mounted || serial != _loadSerial) {
        return;
      }
      setState(() {
        _dashboard = dashboard;
        _cacheDashboardQuotes(dashboard);
      });
    } catch (error) {
      if (!mounted || serial != _loadSerial) {
        return;
      }
      setState(() => _dashboardError = error.toString());
    } finally {
      if (mounted && serial == _loadSerial) {
        setState(() => _loadingDashboard = false);
      }
    }
  }

  void _loadStoredWatchlists() {
    _domesticWatchlistGroups = _readStoredWatchlistGroups(
      groupStore: _domesticWatchlistGroupStore,
      legacyStore: _domesticLegacyWatchlistStore,
      marketCode: 'KR',
    );
    _overseasWatchlistGroups = _readStoredWatchlistGroups(
      groupStore: _overseasWatchlistGroupStore,
      legacyStore: _overseasLegacyWatchlistStore,
      marketCode: 'US',
    );
    _domesticWatchlistGroupStore.writeRaw(
      _encodeStockTradingWatchlistGroups(_domesticWatchlistGroups),
    );
    _overseasWatchlistGroupStore.writeRaw(
      _encodeStockTradingWatchlistGroups(_overseasWatchlistGroups),
    );
  }

  bool _addWatchlistSymbol(String rawSymbol) {
    final symbol = _normalizeStockTradingSymbol(
      rawSymbol,
      marketCode: _marketCode,
    );
    if (symbol.isEmpty) {
      return false;
    }

    final targetGroupId =
        _currentSelectedWatchlistGroupId == _stockTradingAllWatchlistGroupId
        ? _stockTradingDefaultWatchlistGroupId
        : _currentSelectedWatchlistGroupId;
    final currentGroups = _ensureStockTradingDefaultWatchlistGroup(
      _currentWatchlistGroups,
      marketCode: _marketCode,
    );
    var groupFound = false;
    final nextGroups = currentGroups
        .map((group) {
          if (group.id != targetGroupId) {
            return group;
          }
          groupFound = true;
          final nextSymbols = List<String>.from(group.symbols);
          if (!nextSymbols.contains(symbol)) {
            nextSymbols.add(symbol);
          }
          return group.copyWith(symbols: List.unmodifiable(nextSymbols));
        })
        .toList(growable: true);
    if (!groupFound) {
      final defaultSymbols = <String>[symbol];
      nextGroups.add(
        _StockTradingWatchlistGroup(
          id: _stockTradingDefaultWatchlistGroupId,
          name: _stockTradingDefaultWatchlistGroupName,
          symbols: List.unmodifiable(defaultSymbols),
        ),
      );
    }
    final normalizedGroups = List<_StockTradingWatchlistGroup>.unmodifiable(
      nextGroups,
    );
    setState(() {
      if (_selectedMarket == _StockTradingMarket.domestic) {
        _selectedDomesticSymbol = symbol;
        _domesticWatchlistGroups = normalizedGroups;
        _domesticWatchlistGroupStore.writeRaw(
          _encodeStockTradingWatchlistGroups(_domesticWatchlistGroups),
        );
      } else {
        _selectedOverseasSymbol = symbol;
        _overseasWatchlistGroups = normalizedGroups;
        _overseasWatchlistGroupStore.writeRaw(
          _encodeStockTradingWatchlistGroups(_overseasWatchlistGroups),
        );
      }
      _dashboardError = null;
    });
    _loadDashboard();
    return true;
  }

  bool _createWatchlistGroup(String rawName) {
    final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      return false;
    }
    final currentGroups = _ensureStockTradingDefaultWatchlistGroup(
      _currentWatchlistGroups,
      marketCode: _marketCode,
    );
    for (final group in currentGroups) {
      if (group.name.toLowerCase() == name.toLowerCase()) {
        _selectWatchlistGroup(group.id);
        return false;
      }
    }

    final groupId = _createStockTradingWatchlistGroupId(name, currentGroups);
    final nextGroups = List<_StockTradingWatchlistGroup>.unmodifiable([
      ...currentGroups,
      _StockTradingWatchlistGroup(
        id: groupId,
        name: name,
        symbols: const <String>[],
      ),
    ]);
    setState(() {
      if (_selectedMarket == _StockTradingMarket.domestic) {
        _domesticWatchlistGroups = nextGroups;
        _selectedDomesticWatchlistGroupId = groupId;
        _domesticWatchlistGroupStore.writeRaw(
          _encodeStockTradingWatchlistGroups(_domesticWatchlistGroups),
        );
      } else {
        _overseasWatchlistGroups = nextGroups;
        _selectedOverseasWatchlistGroupId = groupId;
        _overseasWatchlistGroupStore.writeRaw(
          _encodeStockTradingWatchlistGroups(_overseasWatchlistGroups),
        );
      }
    });
    return true;
  }

  void _selectWatchlistGroup(String groupId) {
    if (groupId != _stockTradingAllWatchlistGroupId &&
        !_currentWatchlistGroups.any((group) => group.id == groupId)) {
      return;
    }
    setState(() {
      if (_selectedMarket == _StockTradingMarket.domestic) {
        _selectedDomesticWatchlistGroupId = groupId;
      } else {
        _selectedOverseasWatchlistGroupId = groupId;
      }
    });
  }

  void _changeMarket(_StockTradingMarket market) {
    if (_selectedMarket == market) {
      return;
    }
    setState(() {
      _selectedMarket = market;
      _dashboard = null;
      _dashboardError = null;
      _selectedInterval = _StockTradingChartInterval.day;
    });
    _loadDashboard();
  }

  void _changeWorkspace(_StockTradingWorkspace workspace) {
    if (_activeWorkspace == workspace) {
      return;
    }
    setState(() => _activeWorkspace = workspace);
  }

  void _selectSymbol(String symbol) {
    if (_activeSymbol == symbol) {
      return;
    }
    setState(() {
      if (_selectedMarket == _StockTradingMarket.domestic) {
        _selectedDomesticSymbol = symbol;
      } else {
        _selectedOverseasSymbol = symbol;
      }
      _dashboardError = null;
    });
    _loadDashboard();
  }

  void _cacheDashboardQuotes(TossStockDashboard dashboard) {
    final market = dashboard.summary.market.trim().toUpperCase();
    if (market.isEmpty) {
      return;
    }
    for (final quote in dashboard.watchlist) {
      final symbol = quote.symbol.trim().toUpperCase();
      if (symbol.isEmpty || !quote.hasPrice) {
        continue;
      }
      _quoteCache['$market:$symbol'] = quote;
    }
  }

  void _changeInterval(_StockTradingChartInterval interval) {
    if (_selectedInterval == interval) {
      return;
    }
    final previousSourceInterval = _selectedInterval.sourceInterval;
    setState(() => _selectedInterval = interval);
    if (previousSourceInterval != interval.sourceInterval) {
      _loadDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;

    return Scaffold(
      backgroundColor: _stockCanvasColor,
      body: SafeArea(
        child: Column(
          children: [
            _StockTradingTopBar(
              config: config,
              selectedMarket: _selectedMarket,
              onMarketChanged: _changeMarket,
              dashboard: _currentMarketDashboard,
              loading: _loadingDashboard,
              error: _dashboardError,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1100;
                  final medium = constraints.maxWidth >= 820;
                  final padding = constraints.maxWidth < 720 ? 10.0 : 14.0;
                  final currentMarketDashboard = _currentMarketDashboard;
                  final activeDashboard = _activeDashboard;
                  final currentMarketQuotes = _currentMarketQuotes;
                  final activeQuote = _activeQuote;
                  final watchlistPanel = _StockTradingWatchlistPanel(
                    api: _tossStockApi,
                    config: config,
                    quotes: currentMarketQuotes,
                    groups: _currentWatchlistGroups,
                    selectedGroupId: _currentSelectedWatchlistGroupId,
                    addTargetGroupName: _currentWatchlistAddTargetName,
                    customSymbols: _currentVisibleWatchlistSymbols,
                    selectedSymbol: _activeSymbol,
                    onSymbolSelected: _selectSymbol,
                    onGroupSelected: _selectWatchlistGroup,
                    onGroupCreated: _createWatchlistGroup,
                    onSymbolAdded: _addWatchlistSymbol,
                  );
                  final marketBoard = _StockTradingMarketBoard(
                    api: _tossStockApi,
                    config: config,
                    marketCode: _marketCode,
                    symbol: _activeSymbol,
                    dashboard: activeDashboard,
                    quote: activeQuote,
                    loading: _loadingDashboard,
                    error: _dashboardError,
                    selectedInterval: _selectedInterval,
                    onIntervalChanged: _changeInterval,
                  );
                  final chartWorkspace = _StockTradingChartWorkspace(
                    api: _tossStockApi,
                    config: config,
                    marketCode: _marketCode,
                    symbol: _activeSymbol,
                    dashboard: activeDashboard,
                    quote: activeQuote,
                    loading: _loadingDashboard,
                    error: _dashboardError,
                    selectedInterval: _selectedInterval,
                    onIntervalChanged: _changeInterval,
                    quotes: currentMarketQuotes,
                    onSymbolSelected: _selectSymbol,
                  );
                  final strategyPanel = _StockTradingStrategyPanel(
                    config: config,
                    marketCode: _marketCode,
                    selectedSymbol: _activeSymbol,
                    quotes: currentMarketQuotes,
                    dashboard: currentMarketDashboard,
                    activeDashboard: activeDashboard,
                    quote: activeQuote,
                    loading: _loadingDashboard,
                    error: _dashboardError,
                    onSymbolSelected: _selectSymbol,
                  );
                  final orderPanel = _StockTradingOrderPanel(
                    api: _tossStockApi,
                    config: config,
                    marketCode: _marketCode,
                    symbol: _activeSymbol,
                    dashboard: currentMarketDashboard,
                    quote: activeQuote,
                    loading: _loadingDashboard,
                    onOrderSubmitted: _loadDashboard,
                  );
                  final orderWorkspace = _StockTradingOrderWorkspace(
                    config: config,
                    dashboard: activeDashboard ?? currentMarketDashboard,
                    quote: activeQuote,
                    loading: _loadingDashboard,
                    error: _dashboardError,
                  );
                  final executionPanel = _StockTradingExecutionPanel(
                    config: config,
                    dashboard: currentMarketDashboard,
                    loading: _loadingDashboard,
                    error: _dashboardError,
                  );
                  final executionWorkspace = _StockTradingExecutionWorkspace(
                    config: config,
                    dashboard: currentMarketDashboard,
                    loading: _loadingDashboard,
                    error: _dashboardError,
                  );

                  if (!medium) {
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                        children: [
                          SizedBox(height: 420, child: watchlistPanel),
                          const SizedBox(height: 10),
                          SizedBox(height: 760, child: chartWorkspace),
                          const SizedBox(height: 10),
                          SizedBox(height: 680, child: strategyPanel),
                          const SizedBox(height: 10),
                          SizedBox(height: 700, child: orderWorkspace),
                          const SizedBox(height: 10),
                          SizedBox(height: 700, child: executionWorkspace),
                          const SizedBox(height: 10),
                          SizedBox(height: 390, child: orderPanel),
                          const SizedBox(height: 10),
                          SizedBox(height: 210, child: executionPanel),
                        ],
                      ),
                    );
                  }

                  Widget mainWorkspace;
                  switch (_activeWorkspace) {
                    case _StockTradingWorkspace.chart:
                      mainWorkspace = chartWorkspace;
                    case _StockTradingWorkspace.orders:
                      mainWorkspace = orderWorkspace;
                    case _StockTradingWorkspace.executions:
                      mainWorkspace = executionWorkspace;
                    case _StockTradingWorkspace.strategy:
                      mainWorkspace = strategyPanel;
                    case _StockTradingWorkspace.watchlist:
                      mainWorkspace = _StockTradingResizableVerticalSplit(
                        first: watchlistPanel,
                        second: marketBoard,
                        ratio: _watchlistWorkspaceSplitRatio,
                        minFirstExtent: 220,
                        minSecondExtent: 260,
                        handleExtent: padding,
                        onRatioChanged: (value) => setState(
                          () => _watchlistWorkspaceSplitRatio = value,
                        ),
                        onReset: () => setState(
                          () => _watchlistWorkspaceSplitRatio = 5 / 9,
                        ),
                      );
                  }

                  final contentWidth =
                      constraints.maxWidth - 58 - (padding * 2);
                  final resizeHandleWidth = math.max(12.0, padding);
                  final defaultRightWidth = wide ? 340.0 : 304.0;
                  final minRightWidth = contentWidth >= 980 ? 304.0 : 260.0;
                  final maxRightWidth = math.max(
                    minRightWidth,
                    math.min(520.0, contentWidth - resizeHandleWidth - 420.0),
                  );
                  final rightColumnWidth =
                      (_rightColumnWidth ?? defaultRightWidth)
                          .clamp(minRightWidth, maxRightWidth)
                          .toDouble();
                  final rightColumn = _StockTradingResizableVerticalSplit(
                    first: orderPanel,
                    second: executionPanel,
                    ratio: _rightColumnSplitRatio,
                    minFirstExtent: 300,
                    minSecondExtent: 220,
                    handleExtent: padding,
                    onRatioChanged: (value) =>
                        setState(() => _rightColumnSplitRatio = value),
                    onReset: () =>
                        setState(() => _rightColumnSplitRatio = 5 / 8),
                  );

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StockTradingSideRail(
                        color: config.color,
                        active: _activeWorkspace,
                        onChanged: _changeWorkspace,
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(padding),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: mainWorkspace),
                              _StockTradingResizeHandle(
                                vertical: true,
                                extent: resizeHandleWidth,
                                tooltip: '패널 너비 조정',
                                onDragDelta: (delta) {
                                  setState(() {
                                    _rightColumnWidth =
                                        (rightColumnWidth - delta)
                                            .clamp(minRightWidth, maxRightWidth)
                                            .toDouble();
                                  });
                                },
                                onReset: () =>
                                    setState(() => _rightColumnWidth = null),
                              ),
                              SizedBox(
                                width: rightColumnWidth,
                                child: rightColumn,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTradingResizableVerticalSplit extends StatelessWidget {
  const _StockTradingResizableVerticalSplit({
    required this.first,
    required this.second,
    required this.ratio,
    required this.minFirstExtent,
    required this.minSecondExtent,
    required this.handleExtent,
    required this.onRatioChanged,
    required this.onReset,
  });

  final Widget first;
  final Widget second;
  final double ratio;
  final double minFirstExtent;
  final double minSecondExtent;
  final double handleExtent;
  final ValueChanged<double> onRatioChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalExtent = constraints.maxHeight;
        if (!totalExtent.isFinite || totalExtent <= 0) {
          return Column(
            children: [
              Expanded(child: first),
              _StockTradingResizeHandle(
                vertical: false,
                extent: handleExtent,
                tooltip: '패널 높이 조정',
                onDragDelta: (_) {},
                onReset: onReset,
              ),
              Expanded(child: second),
            ],
          );
        }

        final handle = math.min(handleExtent, totalExtent);
        final adjustableExtent = math.max(0.0, totalExtent - handle);
        var firstMinimum = math.min(minFirstExtent, adjustableExtent);
        var secondMinimum = math.min(minSecondExtent, adjustableExtent);
        if (firstMinimum + secondMinimum > adjustableExtent &&
            firstMinimum + secondMinimum > 0) {
          final scale = adjustableExtent / (firstMinimum + secondMinimum);
          firstMinimum *= scale;
          secondMinimum *= scale;
        }
        final maxFirstExtent = math.max(
          firstMinimum,
          adjustableExtent - secondMinimum,
        );
        final firstExtent = (adjustableExtent * ratio)
            .clamp(firstMinimum, maxFirstExtent)
            .toDouble();
        final secondExtent = math.max(0.0, adjustableExtent - firstExtent);

        return Column(
          children: [
            SizedBox(height: firstExtent, child: first),
            _StockTradingResizeHandle(
              vertical: false,
              extent: handle,
              tooltip: '패널 높이 조정',
              onDragDelta: (delta) {
                if (adjustableExtent <= 0) {
                  return;
                }
                final nextFirstExtent = (firstExtent + delta)
                    .clamp(firstMinimum, maxFirstExtent)
                    .toDouble();
                onRatioChanged(nextFirstExtent / adjustableExtent);
              },
              onReset: onReset,
            ),
            SizedBox(height: secondExtent, child: second),
          ],
        );
      },
    );
  }
}

class _StockTradingResizeHandle extends StatelessWidget {
  const _StockTradingResizeHandle({
    required this.vertical,
    required this.extent,
    required this.tooltip,
    required this.onDragDelta,
    required this.onReset,
  });

  final bool vertical;
  final double extent;
  final String tooltip;
  final ValueChanged<double> onDragDelta;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final cursor = vertical
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown;
    final indicatorWidth = vertical ? 3.0 : 46.0;
    final indicatorHeight = vertical ? 46.0 : 3.0;

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (details) =>
              onDragDelta(vertical ? details.delta.dx : details.delta.dy),
          onDoubleTap: onReset,
          child: SizedBox(
            width: vertical ? extent : double.infinity,
            height: vertical ? double.infinity : extent,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _stockPanelBorderColor.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: KangColors.ink.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SizedBox(width: indicatorWidth, height: indicatorHeight),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _stockTradingTopStatusText({
  required TossStockDashboard? dashboard,
  required bool loading,
  required String? error,
}) {
  if (dashboard?.summary.tradingAvailable == true) {
    return '실전 주문 가능';
  }
  if (dashboard?.hasLiveData == true) {
    return '실시간 시세';
  }
  if (loading) {
    return '실전 연결 중';
  }
  if (error?.trim().isNotEmpty == true) {
    return '연결 확인 필요';
  }
  return '실전 구성';
}

class _StockTradingTopBar extends StatelessWidget {
  const _StockTradingTopBar({
    required this.config,
    required this.selectedMarket,
    required this.onMarketChanged,
    required this.dashboard,
    required this.loading,
    required this.error,
  });

  final _StockTradingMarketConfig config;
  final _StockTradingMarket selectedMarket;
  final ValueChanged<_StockTradingMarket> onMarketChanged;
  final TossStockDashboard? dashboard;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final statusText = _stockTradingTopStatusText(
      dashboard: dashboard,
      loading: loading,
      error: error,
    );
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: _stockSurfaceColor,
        border: Border(bottom: BorderSide(color: _stockPanelBorderColor)),
        boxShadow: [
          BoxShadow(
            color: Color(0x080B1220),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '뒤로',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: config.color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: config.color.withValues(alpha: 0.16)),
            ),
            child: Icon(Icons.show_chart_rounded, color: config.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '주식 거래 대시보드',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: KangColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${config.title} · ${config.description}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: _StockTradingMarketTabs(
              selected: selectedMarket,
              onChanged: onMarketChanged,
            ),
          ),
          const SizedBox(width: 12),
          _StatusPill(text: statusText, color: config.color),
        ],
      ),
    );
  }
}

class _StockTradingSideRail extends StatelessWidget {
  const _StockTradingSideRail({
    required this.color,
    required this.active,
    required this.onChanged,
  });

  final Color color;
  final _StockTradingWorkspace active;
  final ValueChanged<_StockTradingWorkspace> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: _stockRailColor,
        border: Border(right: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.show_chart_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 28,
            height: 1,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 10),
          _StockTradingRailButton(
            icon: Icons.favorite_rounded,
            label: '관심종목',
            selected: active == _StockTradingWorkspace.watchlist,
            color: color,
            onTap: () => onChanged(_StockTradingWorkspace.watchlist),
          ),
          _StockTradingRailButton(
            icon: Icons.candlestick_chart_rounded,
            label: '차트',
            selected: active == _StockTradingWorkspace.chart,
            color: color,
            onTap: () => onChanged(_StockTradingWorkspace.chart),
          ),
          _StockTradingRailButton(
            icon: Icons.price_change_rounded,
            label: '주문',
            selected: active == _StockTradingWorkspace.orders,
            color: color,
            onTap: () => onChanged(_StockTradingWorkspace.orders),
          ),
          _StockTradingRailButton(
            icon: Icons.receipt_long_rounded,
            label: '체결',
            selected: active == _StockTradingWorkspace.executions,
            color: color,
            onTap: () => onChanged(_StockTradingWorkspace.executions),
          ),
          _StockTradingRailButton(
            icon: Icons.auto_graph_rounded,
            label: '전략 투자',
            selected: active == _StockTradingWorkspace.strategy,
            color: color,
            onTap: () => onChanged(_StockTradingWorkspace.strategy),
          ),
          const Spacer(),
          Tooltip(
            message: 'LIVE',
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF19C37D),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingRailButton extends StatelessWidget {
  const _StockTradingRailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Material(
            color: selected
                ? color.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: selected
                      ? Border.all(color: color.withValues(alpha: 0.72))
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.58),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StockTradingPanel extends StatelessWidget {
  const _StockTradingPanel({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
        boxShadow: _stockPanelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              color: _stockPanelHeaderColor,
              border: Border(bottom: BorderSide(color: _stockPanelBorderColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.12)),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _StockTradingWatchlistPanel extends StatefulWidget {
  const _StockTradingWatchlistPanel({
    required this.api,
    required this.config,
    required this.quotes,
    required this.groups,
    required this.selectedGroupId,
    required this.addTargetGroupName,
    required this.customSymbols,
    required this.selectedSymbol,
    required this.onSymbolSelected,
    required this.onGroupSelected,
    required this.onGroupCreated,
    required this.onSymbolAdded,
  });

  final TossStockApi api;
  final _StockTradingMarketConfig config;
  final List<TossStockQuote> quotes;
  final List<_StockTradingWatchlistGroup> groups;
  final String selectedGroupId;
  final String addTargetGroupName;
  final List<String> customSymbols;
  final String selectedSymbol;
  final ValueChanged<String> onSymbolSelected;
  final ValueChanged<String> onGroupSelected;
  final bool Function(String name) onGroupCreated;
  final bool Function(String symbol) onSymbolAdded;

  @override
  State<_StockTradingWatchlistPanel> createState() =>
      _StockTradingWatchlistPanelState();
}

class _StockTradingWatchlistPanelState
    extends State<_StockTradingWatchlistPanel> {
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  var _searchQuery = '';
  var _loadingSearch = false;
  var _searchSerial = 0;
  String? _searchError;
  List<TossStockSearchItem> _searchResults = const [];
  final Map<String, _StockTradingDailyChange> _dailyChanges = {};
  final Set<String> _loadingDailyChangeSymbols = {};
  var _dailyChangeSerial = 0;

  bool get _usesRemoteSearch => widget.config.badge == 'KRW';
  String get _marketCode => widget.config.badge == 'KRW' ? 'KR' : 'US';

  @override
  void initState() {
    super.initState();
    _scheduleDailyChangeRefresh();
  }

  @override
  void didUpdateWidget(covariant _StockTradingWatchlistPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final marketChanged = oldWidget.config.badge != widget.config.badge;
    if (marketChanged) {
      _searchDebounce?.cancel();
      _searchSerial += 1;
      _dailyChangeSerial += 1;
      _dailyChanges.clear();
      _loadingDailyChangeSymbols.clear();
      _searchResults = const [];
      _searchError = null;
      _loadingSearch = false;
      if (_usesRemoteSearch && _searchQuery.trim().isNotEmpty) {
        _searchDebounce = Timer(
          Duration.zero,
          () => _runRemoteSearch(_searchQuery),
        );
      }
    }
    _scheduleDailyChangeRefresh();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleDailyChangeRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshMissingDailyChanges();
      }
    });
  }

  void _refreshMissingDailyChanges() {
    final marketCode = widget.config.badge == 'KRW' ? 'KR' : 'US';
    final serial = _dailyChangeSerial;
    for (final quote in widget.quotes) {
      final symbol = quote.symbol.trim().toUpperCase();
      if (symbol.isEmpty || !quote.hasPrice) {
        continue;
      }
      if (quote.changePercentValue != null || quote.changeValue != null) {
        continue;
      }

      final lastPrice = quote.lastPrice.trim();
      final cached = _dailyChanges[symbol];
      if (cached != null && cached.lastPrice == lastPrice) {
        continue;
      }
      if (_loadingDailyChangeSymbols.contains(symbol)) {
        continue;
      }
      _loadDailyChange(
        marketCode: marketCode,
        symbol: symbol,
        lastPrice: lastPrice,
        serial: serial,
      );
    }
  }

  Future<void> _loadDailyChange({
    required String marketCode,
    required String symbol,
    required String lastPrice,
    required int serial,
  }) async {
    _loadingDailyChangeSymbols.add(symbol);
    try {
      final result = await widget.api.loadCandles(
        market: marketCode,
        symbol: symbol,
        candleInterval: '1d',
        count: 30,
      );
      if (!mounted || serial != _dailyChangeSerial) {
        return;
      }
      final latestQuote = _stockQuoteForSymbol(widget.quotes, symbol);
      final effectiveLastPrice =
          latestQuote?.lastPrice.trim().isNotEmpty == true
          ? latestQuote!.lastPrice.trim()
          : lastPrice;
      final change = _stockDailyChangeFromCandles(
        result.candles,
        lastPrice: effectiveLastPrice,
      );
      if (change == null) {
        return;
      }
      setState(() => _dailyChanges[symbol] = change);
    } catch (_) {
      // Keep the row usable with price data even if a secondary change lookup fails.
    } finally {
      _loadingDailyChangeSymbols.remove(symbol);
    }
  }

  void _handleSearchChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    _searchSerial += 1;
    setState(() {
      _searchQuery = value;
      _searchError = null;
      if (query.isEmpty || !_usesRemoteSearch) {
        _searchResults = const [];
        _loadingSearch = false;
      }
    });

    if (query.isEmpty || !_usesRemoteSearch) {
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 280),
      () => _runRemoteSearch(query),
    );
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchSerial += 1;
    setState(() {
      _searchQuery = '';
      _searchResults = const [];
      _searchError = null;
      _loadingSearch = false;
    });
  }

  Future<void> _runRemoteSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty || !_usesRemoteSearch) {
      return;
    }

    final serial = _searchSerial;
    setState(() {
      _loadingSearch = true;
      _searchError = null;
    });

    try {
      final result = await widget.api.searchStocks(
        market: 'KR',
        query: query,
        limit: 30,
      );
      if (!mounted || serial != _searchSerial || query != _searchQuery.trim()) {
        return;
      }
      setState(() {
        _searchResults = result.items;
        _loadingSearch = false;
      });
    } catch (error) {
      if (!mounted || serial != _searchSerial || query != _searchQuery.trim()) {
        return;
      }
      setState(() {
        _searchResults = const [];
        _searchError = error.toString();
        _loadingSearch = false;
      });
    }
  }

  Future<void> _showAddSymbolDialog(
    List<_StockTradingWatchlistItem> currentItems,
  ) async {
    final rawSymbol = await showDialog<String>(
      context: context,
      builder: (_) => _StockTradingAddSymbolDialog(
        api: widget.api,
        config: widget.config,
        currentItems: currentItems,
        initialQuery: _searchQuery.trim(),
        addTargetGroupName: widget.addTargetGroupName,
      ),
    );
    if (!mounted || rawSymbol == null) {
      return;
    }
    _addSymbolToWatchlist(rawSymbol, currentItems);
  }

  Future<void> _showCreateGroupDialog() async {
    final controller = TextEditingController();
    final groupName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Watchlist 그룹 추가'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '그룹 이름',
              hintText: '예: 반도체, 배당주',
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('추가'),
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted || groupName == null) {
      return;
    }
    final normalizedName = groupName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedName.isEmpty) {
      _showWatchlistSnack('그룹 이름을 입력해 주세요.');
      return;
    }
    final created = widget.onGroupCreated(normalizedName);
    _showWatchlistSnack(
      created ? '$normalizedName 그룹을 추가했습니다.' : '이미 있는 그룹입니다.',
    );
  }

  void _addItemToWatchlist(
    _StockTradingWatchlistItem item,
    List<_StockTradingWatchlistItem> currentItems,
  ) {
    _addSymbolToWatchlist(item.symbol, currentItems);
  }

  void _addSymbolToWatchlist(
    String rawSymbol,
    List<_StockTradingWatchlistItem> currentItems,
  ) {
    final symbol = _normalizeStockTradingSymbol(
      rawSymbol,
      marketCode: _marketCode,
    );
    if (symbol.isEmpty) {
      _showWatchlistSnack('종목 코드를 확인해 주세요.');
      return;
    }

    if (_stockTradingWatchlistContainsSymbol(currentItems, symbol)) {
      widget.onSymbolSelected(symbol);
      _showWatchlistSnack('이미 Watchlist에 있는 종목입니다.');
      return;
    }

    final added = widget.onSymbolAdded(symbol);
    if (!added) {
      _showWatchlistSnack('종목 코드를 확인해 주세요.');
      return;
    }

    _clearSearch();
    _showWatchlistSnack('$symbol 종목을 ${widget.addTargetGroupName}에 추가했습니다.');
  }

  void _showWatchlistSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final selectedSymbol = widget.selectedSymbol;
    final onSymbolSelected = widget.onSymbolSelected;
    final baseItems = config.badge == 'KRW'
        ? const [
            _StockTradingWatchlistItem(
              symbol: '005930',
              name: '삼성전자',
              logoAsset: 'assets/stock_logos/005930.png',
              price: '339,500 KRW',
              change: '+9.34%',
              changeValue: 9.34,
              marketCap: '1984.8조원',
              market: 'KOSPI',
            ),
            _StockTradingWatchlistItem(
              symbol: '000660',
              name: 'SK하이닉스',
              logoAsset: 'assets/stock_logos/000660.png',
              price: '2,653,000 KRW',
              change: '+3.27%',
              changeValue: 3.27,
              marketCap: '1890.8조원',
              market: 'KOSPI',
            ),
            _StockTradingWatchlistItem(
              symbol: '035420',
              name: 'NAVER',
              logoAsset: 'assets/stock_logos/035420.png',
              price: '201,000 KRW',
              change: '+0.60%',
              changeValue: 0.60,
              marketCap: '31.5조원',
              market: 'KOSPI',
            ),
            _StockTradingWatchlistItem(
              symbol: '035720',
              name: '카카오',
              logoAsset: 'assets/stock_logos/035720.png',
              price: '34,150 KRW',
              change: '+0.15%',
              changeValue: 0.15,
              marketCap: '15.1조원',
              market: 'KOSPI',
            ),
            _StockTradingWatchlistItem(
              symbol: '068270',
              name: '셀트리온',
              logoAsset: 'assets/stock_logos/068270.png',
              price: '172,900 KRW',
              change: '+9.03%',
              changeValue: 9.03,
              marketCap: '38.0조원',
              market: 'KOSPI',
            ),
          ]
        : const [
            _StockTradingWatchlistItem(
              symbol: 'NVDA',
              name: 'NVIDIA',
              logoAsset: 'assets/stock_logos/NVDA.png',
              price: '202.30 USD',
              change: '+1.10%',
              changeValue: 1.10,
              marketCap: '4.9T',
              market: 'NASDAQ',
            ),
            _StockTradingWatchlistItem(
              symbol: 'AAPL',
              name: 'Apple',
              logoAsset: 'assets/stock_logos/AAPL.png',
              price: '297.02 USD',
              change: '+0.92%',
              changeValue: 0.92,
              marketCap: '4.4T',
              market: 'NASDAQ',
            ),
            _StockTradingWatchlistItem(
              symbol: 'MSFT',
              name: 'Microsoft',
              logoAsset: 'assets/stock_logos/MSFT.png',
              price: '492.14 USD',
              change: '-0.18%',
              changeValue: -0.18,
              marketCap: '3.6T',
              market: 'NASDAQ',
            ),
            _StockTradingWatchlistItem(
              symbol: 'TSLA',
              name: 'Tesla',
              logoAsset: 'assets/stock_logos/TSLA.png',
              price: '429.90 USD',
              change: '+0.74%',
              changeValue: 0.74,
              marketCap: '1.4T',
              market: 'NASDAQ',
            ),
          ];
    final selectedGroupId = widget.selectedGroupId;
    final showsDefaultUniverse =
        selectedGroupId == _stockTradingAllWatchlistGroupId ||
        selectedGroupId == _stockTradingDefaultWatchlistGroupId;
    final items = _stockTradingWatchlistItemsWithQuotes(
      showsDefaultUniverse ? baseItems : const <_StockTradingWatchlistItem>[],
      widget.quotes,
      _dailyChanges,
      widget.customSymbols,
      marketCode: _marketCode,
      includeRemainingQuotes: showsDefaultUniverse,
    );
    final currentWatchlistSymbols = items
        .map((item) => item.symbol.trim().toUpperCase())
        .where((symbol) => symbol.isNotEmpty)
        .toSet();
    final hasQuery = _searchQuery.trim().isNotEmpty;
    final localFilteredItems = _filterStockTradingWatchlistItems(
      items,
      _searchQuery,
    );
    final remoteSearchItems = _searchResults
        .map((item) => _stockTradingItemFromSearchResult(item, items))
        .toList(growable: false);
    final displayItems = hasQuery
        ? _usesRemoteSearch
              ? remoteSearchItems.isNotEmpty
                    ? remoteSearchItems
                    : localFilteredItems
              : localFilteredItems
        : items;
    final showSearchLoading =
        hasQuery && _usesRemoteSearch && _loadingSearch && displayItems.isEmpty;
    final showSearchError =
        hasQuery && _searchError != null && displayItems.isEmpty;

    return _StockTradingPanel(
      title: 'Watchlist',
      icon: Icons.favorite_border_rounded,
      color: config.color,
      trailing: _StatusPill(text: config.badge, color: config.color),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _handleSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, color: config.color),
                    suffixIcon: _searchQuery.trim().isEmpty
                        ? const Icon(Icons.tune_rounded, size: 18)
                        : IconButton(
                            tooltip: '검색 지우기',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _clearSearch,
                          ),
                    hintText: 'Symbol / Name',
                    filled: true,
                    fillColor: _stockSurfaceMutedColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _stockPanelBorderColor.withValues(alpha: 0.95),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _stockPanelBorderColor.withValues(alpha: 0.95),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: config.color),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _StockTradingWatchlistChip(
                              text: '전체',
                              selected:
                                  selectedGroupId ==
                                  _stockTradingAllWatchlistGroupId,
                              color: config.color,
                              onTap: () => widget.onGroupSelected(
                                _stockTradingAllWatchlistGroupId,
                              ),
                            ),
                            const SizedBox(width: 6),
                            for (final group in widget.groups) ...[
                              _StockTradingWatchlistChip(
                                text: group.name,
                                selected: selectedGroupId == group.id,
                                color: config.color,
                                onTap: () => widget.onGroupSelected(group.id),
                              ),
                              const SizedBox(width: 6),
                            ],
                            _StockTradingWatchlistChip(
                              text: '그룹',
                              selected: false,
                              color: config.color,
                              icon: Icons.add_rounded,
                              onTap: _showCreateGroupDialog,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Watchlist 추가',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      onPressed: () => _showAddSymbolDialog(items),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: showSearchLoading
                    ? _StockTradingWatchlistStatus(
                        icon: Icons.cloud_sync_rounded,
                        title: '종목을 검색하고 있습니다.',
                        message: _searchQuery.trim(),
                        color: config.color,
                      )
                    : showSearchError
                    ? _StockTradingWatchlistStatus(
                        icon: Icons.error_outline_rounded,
                        title: '검색 결과를 불러오지 못했습니다.',
                        message: '잠시 후 다시 검색해 주세요.',
                        color: _stockFallColor,
                      )
                    : displayItems.isEmpty
                    ? _StockTradingWatchlistStatus(
                        icon: Icons.search_off_rounded,
                        title: '검색 결과가 없습니다.',
                        message: '"${_searchQuery.trim()}"와 일치하는 종목이 없습니다.',
                        color: config.color,
                      )
                    : compact
                    ? _StockTradingWatchlistCards(
                        items: displayItems,
                        selectedSymbol: selectedSymbol,
                        color: config.color,
                        currentWatchlistSymbols: currentWatchlistSymbols,
                        onSymbolSelected: onSymbolSelected,
                        onSymbolAdded: hasQuery
                            ? (item) => _addItemToWatchlist(item, items)
                            : null,
                      )
                    : _StockTradingWatchlistTable(
                        items: displayItems,
                        selectedSymbol: selectedSymbol,
                        color: config.color,
                        currentWatchlistSymbols: currentWatchlistSymbols,
                        onSymbolSelected: onSymbolSelected,
                        onSymbolAdded: hasQuery
                            ? (item) => _addItemToWatchlist(item, items)
                            : null,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StockTradingAddSymbolDialog extends StatefulWidget {
  const _StockTradingAddSymbolDialog({
    required this.api,
    required this.config,
    required this.currentItems,
    required this.initialQuery,
    required this.addTargetGroupName,
  });

  final TossStockApi api;
  final _StockTradingMarketConfig config;
  final List<_StockTradingWatchlistItem> currentItems;
  final String initialQuery;
  final String addTargetGroupName;

  @override
  State<_StockTradingAddSymbolDialog> createState() =>
      _StockTradingAddSymbolDialogState();
}

class _StockTradingAddSymbolDialogState
    extends State<_StockTradingAddSymbolDialog> {
  late final TextEditingController _controller;

  Timer? _searchDebounce;
  var _query = '';
  var _loading = false;
  var _serial = 0;
  String? _error;
  List<_StockTradingWatchlistItem> _remoteItems =
      const <_StockTradingWatchlistItem>[];

  bool get _usesRemoteSearch => widget.config.badge == 'KRW';
  String get _marketCode => widget.config.badge == 'KRW' ? 'KR' : 'US';

  List<_StockTradingWatchlistItem> get _localItems {
    final query = _query.trim();
    if (query.isEmpty) {
      return const <_StockTradingWatchlistItem>[];
    }
    return _filterStockTradingWatchlistItems(widget.currentItems, query);
  }

  List<_StockTradingWatchlistItem> get _displayItems =>
      _mergeStockTradingWatchlistItems(_localItems, _remoteItems);

  Set<String> get _currentSymbols => widget.currentItems
      .map((item) => item.symbol.trim().toUpperCase())
      .where((symbol) => symbol.isNotEmpty)
      .toSet();

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _controller = TextEditingController(text: widget.initialQuery);
    if (_query.trim().isNotEmpty && _usesRemoteSearch) {
      _searchDebounce = Timer(Duration.zero, () => _runRemoteSearch(_query));
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleQueryChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    _serial += 1;
    setState(() {
      _query = value;
      _error = null;
      if (query.isEmpty || !_usesRemoteSearch) {
        _remoteItems = const <_StockTradingWatchlistItem>[];
        _loading = false;
      }
    });

    if (query.isEmpty || !_usesRemoteSearch) {
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 280),
      () => _runRemoteSearch(query),
    );
  }

  Future<void> _runRemoteSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty || !_usesRemoteSearch) {
      return;
    }

    final serial = _serial;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.api.searchStocks(
        market: 'KR',
        query: query,
        limit: 30,
      );
      if (!mounted || serial != _serial || query != _query.trim()) {
        return;
      }
      setState(() {
        _remoteItems = result.items
            .map((item) => _stockTradingItemFromSearchResult(item, const []))
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted || serial != _serial || query != _query.trim()) {
        return;
      }
      setState(() {
        _remoteItems = const <_StockTradingWatchlistItem>[];
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _submitDirectInput() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      return;
    }
    final normalized = _normalizeStockTradingSymbol(
      query,
      marketCode: _marketCode,
    );
    if (normalized.isNotEmpty) {
      Navigator.of(context).pop(normalized);
      return;
    }
    final items = _displayItems;
    if (items.length == 1) {
      Navigator.of(context).pop(items.single.symbol);
    }
  }

  void _selectItem(_StockTradingWatchlistItem item) {
    Navigator.of(context).pop(item.symbol);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.config.color;
    final query = _query.trim();
    final items = _displayItems;
    final canSubmitDirect =
        _normalizeStockTradingSymbol(
          query,
          marketCode: _marketCode,
        ).isNotEmpty ||
        items.length == 1;

    return AlertDialog(
      title: const Text('Watchlist 추가'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: '종목 코드 / 이름',
                hintText: widget.config.badge == 'KRW'
                    ? '예: 삼성전자, 005930'
                    : '예: NVIDIA, NVDA',
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onChanged: _handleQueryChanged,
              onSubmitted: (_) => canSubmitDirect ? _submitDirectInput() : null,
            ),
            const SizedBox(height: 10),
            Text(
              '추가 위치: ${widget.addTargetGroupName}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: KangColors.slate,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: _StockTradingAddSearchResults(
                  items: items,
                  query: query,
                  loading: _loading,
                  error: _error,
                  color: color,
                  currentSymbols: _currentSymbols,
                  onSelected: _selectItem,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('추가'),
          onPressed: canSubmitDirect ? _submitDirectInput : null,
        ),
      ],
    );
  }
}

class _StockTradingAddSearchResults extends StatelessWidget {
  const _StockTradingAddSearchResults({
    required this.items,
    required this.query,
    required this.loading,
    required this.error,
    required this.color,
    required this.currentSymbols,
    required this.onSelected,
  });

  final List<_StockTradingWatchlistItem> items;
  final String query;
  final bool loading;
  final String? error;
  final Color color;
  final Set<String> currentSymbols;
  final ValueChanged<_StockTradingWatchlistItem> onSelected;

  @override
  Widget build(BuildContext context) {
    if (items.isNotEmpty) {
      return Material(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        child: ListView.separated(
          shrinkWrap: true,
          itemBuilder: (context, index) {
            final item = items[index];
            final alreadyAdded = currentSymbols.contains(
              item.symbol.trim().toUpperCase(),
            );
            return _StockTradingAddSearchResultTile(
              item: item,
              color: color,
              alreadyAdded: alreadyAdded,
              onTap: () => onSelected(item),
            );
          },
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: _stockPanelBorderColor),
          itemCount: items.length,
        ),
      );
    }

    if (loading) {
      return _StockTradingAddDialogStatus(
        icon: Icons.cloud_sync_rounded,
        title: '종목을 검색하고 있습니다.',
        message: query,
        color: color,
      );
    }

    if (error != null) {
      return const _StockTradingAddDialogStatus(
        icon: Icons.error_outline_rounded,
        title: '검색 결과를 불러오지 못했습니다.',
        message: '잠시 후 다시 검색해 주세요.',
        color: _stockFallColor,
      );
    }

    return _StockTradingAddDialogStatus(
      icon: Icons.search_off_rounded,
      title: '검색 결과가 없습니다.',
      message: '정확한 종목코드를 입력하면 바로 추가할 수 있습니다.',
      color: color,
    );
  }
}

class _StockTradingAddSearchResultTile extends StatelessWidget {
  const _StockTradingAddSearchResultTile({
    required this.item,
    required this.color,
    required this.alreadyAdded,
    required this.onTap,
  });

  final _StockTradingWatchlistItem item;
  final Color color;
  final bool alreadyAdded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            _StockTradingSymbolAvatar(
              symbol: item.symbol,
              name: item.name,
              logoAsset: item.logoAsset,
              logoUrl: item.logoUrl,
              selected: false,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.symbol} · ${item.market}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              alreadyAdded
                  ? Icons.check_circle_rounded
                  : Icons.add_circle_outline_rounded,
              color: alreadyAdded ? color.withValues(alpha: 0.58) : color,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTradingAddDialogStatus extends StatelessWidget {
  const _StockTradingAddDialogStatus({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: _stockSurfaceMutedColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingWatchlistItem {
  const _StockTradingWatchlistItem({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.changeValue,
    required this.marketCap,
    required this.market,
    this.logoAsset = '',
    this.logoUrl = '',
  });

  final String symbol;
  final String name;
  final String logoAsset;
  final String logoUrl;
  final String price;
  final String change;
  final double changeValue;
  final String marketCap;
  final String market;
}

class _StockTradingDailyChange {
  const _StockTradingDailyChange({
    required this.lastPrice,
    required this.change,
    required this.percent,
  });

  final String lastPrice;
  final double change;
  final double percent;
}

List<_StockTradingWatchlistItem> _stockTradingWatchlistItemsWithQuotes(
  List<_StockTradingWatchlistItem> baseItems,
  List<TossStockQuote> quotes,
  Map<String, _StockTradingDailyChange> dailyChanges,
  List<String> customSymbols, {
  required String marketCode,
  bool includeRemainingQuotes = true,
}) {
  final quotesBySymbol = {
    for (final quote in quotes) quote.symbol.trim().toUpperCase(): quote,
  };
  final seenSymbols = <String>{};
  final items = <_StockTradingWatchlistItem>[];

  for (final item in baseItems) {
    final symbol = item.symbol.trim().toUpperCase();
    seenSymbols.add(symbol);
    items.add(
      _stockTradingWatchlistItemFromQuote(
        quotesBySymbol[symbol],
        item,
        dailyChanges[symbol],
      ),
    );
  }

  for (final rawSymbol in customSymbols) {
    final symbol = _normalizeStockTradingSymbol(
      rawSymbol,
      marketCode: marketCode,
    );
    if (symbol.isEmpty || seenSymbols.contains(symbol)) {
      continue;
    }
    seenSymbols.add(symbol);
    items.add(
      _stockTradingWatchlistItemFromQuote(
        quotesBySymbol[symbol],
        _stockTradingWatchlistFallbackItem(symbol, marketCode: marketCode),
        dailyChanges[symbol],
      ),
    );
  }

  if (includeRemainingQuotes) {
    for (final quote in quotes) {
      final symbol = quote.symbol.trim().toUpperCase();
      if (symbol.isEmpty || seenSymbols.contains(symbol)) {
        continue;
      }
      seenSymbols.add(symbol);
      items.add(
        _stockTradingWatchlistItemFromQuote(quote, null, dailyChanges[symbol]),
      );
    }
  }

  return items;
}

_StockTradingWatchlistItem _stockTradingWatchlistFallbackItem(
  String symbol, {
  required String marketCode,
}) {
  final normalizedSymbol = _normalizeStockTradingSymbol(
    symbol,
    marketCode: marketCode,
  );
  return _StockTradingWatchlistItem(
    symbol: normalizedSymbol,
    name: normalizedSymbol,
    price: '조회 중',
    change: '-',
    changeValue: 0,
    marketCap: '-',
    market: marketCode == 'KR' ? 'KRX' : 'US',
    logoUrl: _stockTradingLogoUrlForSymbol(normalizedSymbol),
  );
}

TossStockQuote? _stockQuoteForSymbol(
  List<TossStockQuote> quotes,
  String symbol,
) {
  final normalizedSymbol = symbol.trim().toUpperCase();
  if (normalizedSymbol.isEmpty) {
    return null;
  }
  for (final quote in quotes) {
    if (quote.symbol.trim().toUpperCase() == normalizedSymbol) {
      return quote;
    }
  }
  return null;
}

_StockTradingWatchlistItem _stockTradingWatchlistItemFromQuote(
  TossStockQuote? quote,
  _StockTradingWatchlistItem? fallback,
  _StockTradingDailyChange? dailyChange,
) {
  if (quote == null) {
    return fallback!;
  }

  final symbol = quote.symbol.trim().toUpperCase();
  final displayName = quote.displayName.trim().isNotEmpty
      ? quote.displayName.trim()
      : symbol;
  final price = quote.lastPrice.trim().isNotEmpty
      ? '${_stockFormatNumber(quote.lastPrice)} ${quote.currency}'.trim()
      : fallback?.price ?? '선택 후 조회';
  final changePercent = quote.changePercentValue ?? dailyChange?.percent;
  final changeValue =
      changePercent ?? quote.changeValue ?? dailyChange?.change ?? 0;
  final market = quote.market.trim().toUpperCase();
  final logoUrl = fallback?.logoUrl.trim().isNotEmpty == true
      ? fallback!.logoUrl
      : _stockTradingLogoUrlForSymbol(symbol);

  return _StockTradingWatchlistItem(
    symbol: symbol,
    name: displayName,
    logoAsset: fallback?.logoAsset ?? '',
    logoUrl: logoUrl,
    price: price,
    change: _stockWatchlistChangeLabel(quote, fallback, dailyChange),
    changeValue: changeValue,
    marketCap: _stockWatchlistMarketCapLabel(quote, fallback?.marketCap),
    market: market.isNotEmpty ? market : fallback?.market ?? 'KRX',
  );
}

String _stockWatchlistChangeLabel(
  TossStockQuote quote,
  _StockTradingWatchlistItem? fallback,
  _StockTradingDailyChange? dailyChange,
) {
  final percent = quote.changePercentValue ?? dailyChange?.percent;
  if (percent != null) {
    final sign = percent > 0 ? '+' : '';
    return '$sign${percent.toStringAsFixed(2)}%';
  }

  final change = quote.changeValue ?? dailyChange?.change;
  if (change != null) {
    return _stockSignedNumber(change);
  }

  return '-';
}

String _stockWatchlistMarketCapLabel(TossStockQuote quote, String? fallback) {
  final value = quote.marketCapValue;
  if (value == null || value <= 0) {
    return fallback?.trim().isNotEmpty == true ? fallback!.trim() : '-';
  }

  final currency = quote.currency.trim().toUpperCase();
  if (currency == 'KRW') {
    return '${_stockTrimDecimal(value / 1000000000000, digits: 1)}조원';
  }
  if (value >= 1000000000000) {
    return '${_stockTrimDecimal(value / 1000000000000, digits: 2)}T';
  }
  if (value >= 1000000000) {
    return '${_stockTrimDecimal(value / 1000000000, digits: 2)}B';
  }
  return _stockFormatNumber(value.toStringAsFixed(0));
}

String _stockTrimDecimal(num value, {int digits = 2}) {
  final fixed = value.toStringAsFixed(digits);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

List<_StockTradingWatchlistItem> _filterStockTradingWatchlistItems(
  List<_StockTradingWatchlistItem> items,
  String query,
) {
  final normalizedQuery = _normalizeStockTradingSearch(query);
  if (normalizedQuery.isEmpty) {
    return items;
  }
  return items
      .where((item) {
        final text = _normalizeStockTradingSearch(
          '${item.symbol} ${item.name} ${item.market}',
        );
        return text.contains(normalizedQuery);
      })
      .toList(growable: false);
}

List<_StockTradingWatchlistItem> _mergeStockTradingWatchlistItems(
  List<_StockTradingWatchlistItem> primary,
  List<_StockTradingWatchlistItem> secondary,
) {
  final seenSymbols = <String>{};
  final result = <_StockTradingWatchlistItem>[];
  for (final item in [...primary, ...secondary]) {
    final symbol = item.symbol.trim().toUpperCase();
    if (symbol.isEmpty || seenSymbols.contains(symbol)) {
      continue;
    }
    seenSymbols.add(symbol);
    result.add(item);
  }
  return List.unmodifiable(result);
}

_StockTradingWatchlistItem _stockTradingItemFromSearchResult(
  TossStockSearchItem result,
  List<_StockTradingWatchlistItem> currentItems,
) {
  final symbol = result.symbol.trim().toUpperCase();
  for (final item in currentItems) {
    if (item.symbol.toUpperCase() == symbol) {
      return item;
    }
  }

  final name = result.name.trim();
  final market = result.market.trim().toUpperCase();
  return _StockTradingWatchlistItem(
    symbol: symbol,
    name: name.isEmpty ? symbol : name,
    price: '선택 후 조회',
    change: '-',
    changeValue: 0,
    marketCap: '-',
    market: market.isEmpty ? 'KRX' : market,
    logoUrl: _stockTradingLogoUrlForSymbol(symbol),
  );
}

String _normalizeStockTradingSearch(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

List<String> _normalizeStoredWatchlistSymbols(
  List<String> symbols, {
  required String marketCode,
}) {
  final result = <String>[];
  for (final symbol in symbols) {
    final normalized = _normalizeStockTradingSymbol(
      symbol,
      marketCode: marketCode,
    );
    if (normalized.isNotEmpty && !result.contains(normalized)) {
      result.add(normalized);
    }
  }
  return List.unmodifiable(result);
}

List<_StockTradingWatchlistGroup> _readStoredWatchlistGroups({
  required StockFavoritesStore groupStore,
  required StockFavoritesStore legacyStore,
  required String marketCode,
}) {
  final groups = _decodeStockTradingWatchlistGroups(
    groupStore.readRaw(),
    marketCode: marketCode,
  );
  if (groups.isNotEmpty) {
    return groups;
  }

  return _ensureStockTradingDefaultWatchlistGroup([
    _StockTradingWatchlistGroup(
      id: _stockTradingDefaultWatchlistGroupId,
      name: _stockTradingDefaultWatchlistGroupName,
      symbols: _normalizeStoredWatchlistSymbols(
        legacyStore.read(),
        marketCode: marketCode,
      ),
    ),
  ], marketCode: marketCode);
}

List<_StockTradingWatchlistGroup> _decodeStockTradingWatchlistGroups(
  String? raw, {
  required String marketCode,
}) {
  if (raw == null || raw.trim().isEmpty) {
    return const <_StockTradingWatchlistGroup>[];
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <_StockTradingWatchlistGroup>[];
    }
    final rawGroups = decoded['groups'];
    if (rawGroups is! List) {
      return const <_StockTradingWatchlistGroup>[];
    }

    final groups = <_StockTradingWatchlistGroup>[];
    for (final rawGroup in rawGroups) {
      if (rawGroup is! Map<String, dynamic>) {
        continue;
      }
      final id = (rawGroup['id'] as String? ?? '').trim();
      final name = (rawGroup['name'] as String? ?? '').trim();
      final rawSymbols = rawGroup['symbols'];
      final symbols = rawSymbols is List
          ? rawSymbols.whereType<String>().toList(growable: false)
          : const <String>[];
      if (id.isEmpty || name.isEmpty) {
        continue;
      }
      groups.add(
        _StockTradingWatchlistGroup(
          id: id,
          name: name,
          symbols: _normalizeStoredWatchlistSymbols(
            symbols,
            marketCode: marketCode,
          ),
        ),
      );
    }
    return _ensureStockTradingDefaultWatchlistGroup(
      groups,
      marketCode: marketCode,
    );
  } catch (_) {
    return const <_StockTradingWatchlistGroup>[];
  }
}

String _encodeStockTradingWatchlistGroups(
  List<_StockTradingWatchlistGroup> groups,
) {
  return jsonEncode({
    'version': 1,
    'groups': [
      for (final group in groups)
        if (group.id != _stockTradingAllWatchlistGroupId)
          {'id': group.id, 'name': group.name, 'symbols': group.symbols},
    ],
  });
}

List<_StockTradingWatchlistGroup> _ensureStockTradingDefaultWatchlistGroup(
  List<_StockTradingWatchlistGroup> groups, {
  required String marketCode,
}) {
  final defaultSymbols = <String>[];
  final customGroups = <_StockTradingWatchlistGroup>[];
  final seenGroupIds = <String>{_stockTradingDefaultWatchlistGroupId};

  for (final group in groups) {
    final id = group.id.trim();
    final name = group.name.trim();
    if (id.isEmpty || id == _stockTradingAllWatchlistGroupId) {
      continue;
    }
    final symbols = _normalizeStoredWatchlistSymbols(
      group.symbols,
      marketCode: marketCode,
    );
    if (id == _stockTradingDefaultWatchlistGroupId) {
      for (final symbol in symbols) {
        if (!defaultSymbols.contains(symbol)) {
          defaultSymbols.add(symbol);
        }
      }
      continue;
    }
    if (name.isEmpty || seenGroupIds.contains(id)) {
      continue;
    }
    seenGroupIds.add(id);
    customGroups.add(
      _StockTradingWatchlistGroup(id: id, name: name, symbols: symbols),
    );
  }

  return List.unmodifiable([
    _StockTradingWatchlistGroup(
      id: _stockTradingDefaultWatchlistGroupId,
      name: _stockTradingDefaultWatchlistGroupName,
      symbols: List.unmodifiable(defaultSymbols),
    ),
    ...customGroups,
  ]);
}

List<String> _flattenStockTradingWatchlistGroupSymbols(
  List<_StockTradingWatchlistGroup> groups, {
  required String marketCode,
}) {
  final result = <String>[];
  for (final group in groups) {
    for (final symbol in _normalizeStoredWatchlistSymbols(
      group.symbols,
      marketCode: marketCode,
    )) {
      if (!result.contains(symbol)) {
        result.add(symbol);
      }
    }
  }
  return List.unmodifiable(result);
}

String _createStockTradingWatchlistGroupId(
  String name,
  List<_StockTradingWatchlistGroup> groups,
) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final base = slug.isEmpty ? 'group' : slug;
  final usedIds = {
    _stockTradingAllWatchlistGroupId,
    for (final group in groups) group.id,
  };
  var candidate = 'group-$base';
  var suffix = 2;
  while (usedIds.contains(candidate)) {
    candidate = 'group-$base-$suffix';
    suffix += 1;
  }
  return candidate;
}

String _normalizeStockTradingSymbol(
  String value, {
  required String marketCode,
}) {
  final symbol = value.trim().toUpperCase();
  if (marketCode == 'KR') {
    return RegExp(r'^\d{6}$').hasMatch(symbol) ? symbol : '';
  }
  return RegExp(r'^[A-Z0-9.\-]{1,20}$').hasMatch(symbol) ? symbol : '';
}

bool _stockTradingWatchlistContainsSymbol(
  List<_StockTradingWatchlistItem> items,
  String symbol,
) {
  final normalizedSymbol = symbol.trim().toUpperCase();
  return items.any(
    (item) => item.symbol.trim().toUpperCase() == normalizedSymbol,
  );
}

String _stockTradingLogoUrlForSymbol(String symbol) {
  final normalizedSymbol = symbol.trim().toUpperCase();
  if (normalizedSymbol.isEmpty) {
    return '';
  }
  return 'https://static.toss.im/png-icons/securities/icn-sec-fill-$normalizedSymbol.png';
}

class _StockTradingWatchlistChip extends StatelessWidget {
  const _StockTradingWatchlistChip({
    required this.text,
    required this.selected,
    required this.color,
    this.icon,
    this.onTap,
  });

  final String text;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final contentColor = selected ? Colors.white : KangColors.slate;
    return Material(
      color: selected ? color : _stockSurfaceColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.3)
                  : _stockPanelBorderColor.withValues(alpha: 0.9),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: contentColor),
                const SizedBox(width: 4),
              ],
              Text(
                text,
                style: TextStyle(
                  color: contentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTradingWatchlistStatus extends StatelessWidget {
  const _StockTradingWatchlistStatus({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trimmedMessage = message.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KangColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (trimmedMessage.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                trimmedMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StockTradingWatchlistTable extends StatelessWidget {
  const _StockTradingWatchlistTable({
    required this.items,
    required this.selectedSymbol,
    required this.color,
    required this.currentWatchlistSymbols,
    required this.onSymbolSelected,
    this.onSymbolAdded,
  });

  final List<_StockTradingWatchlistItem> items;
  final String selectedSymbol;
  final Color color;
  final Set<String> currentWatchlistSymbols;
  final ValueChanged<String> onSymbolSelected;
  final ValueChanged<_StockTradingWatchlistItem>? onSymbolAdded;

  @override
  Widget build(BuildContext context) {
    final showAddColumn = onSymbolAdded != null;
    return Column(
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: _stockSurfaceMutedColor,
            border: Border.symmetric(
              horizontal: BorderSide(color: _stockPanelBorderColor),
            ),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              color: KangColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
            child: Row(
              children: [
                const SizedBox(width: 42, child: Text('No.')),
                const Expanded(flex: 3, child: Text('Symbol')),
                const Expanded(flex: 2, child: Text('Last Price')),
                const Expanded(flex: 2, child: Text('Change')),
                const Expanded(flex: 2, child: Text('Market Cap')),
                if (showAddColumn) const SizedBox(width: 40, child: Text('추가')),
                const SizedBox(width: 76, child: Text('Market')),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final selected = item.symbol == selectedSymbol;
              return _StockTradingWatchlistTableRow(
                index: index,
                item: item,
                selected: selected,
                color: color,
                canAdd:
                    onSymbolAdded != null &&
                    !currentWatchlistSymbols.contains(
                      item.symbol.trim().toUpperCase(),
                    ),
                onAdd: onSymbolAdded == null
                    ? null
                    : () => onSymbolAdded!(item),
                onTap: () => onSymbolSelected(item.symbol),
              );
            },
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: _stockPanelBorderColor),
            itemCount: items.length,
          ),
        ),
      ],
    );
  }
}

class _StockTradingWatchlistTableRow extends StatelessWidget {
  const _StockTradingWatchlistTableRow({
    required this.index,
    required this.item,
    required this.selected,
    required this.color,
    required this.canAdd,
    this.onAdd,
    required this.onTap,
  });

  final int index;
  final _StockTradingWatchlistItem item;
  final bool selected;
  final Color color;
  final bool canAdd;
  final VoidCallback? onAdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final changeColor = _stockChangeColor(item.changeValue);
    return Material(
      color: selected ? color.withValues(alpha: 0.085) : _stockSurfaceColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: selected
                ? Border(left: BorderSide(color: color, width: 3))
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 16,
                      color: selected ? _stockRiseColor : KangColors.slate,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    _StockTradingSymbolAvatar(
                      symbol: item.symbol,
                      name: item.name,
                      logoAsset: item.logoAsset,
                      logoUrl: item.logoUrl,
                      selected: selected,
                      color: color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: KangColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.symbol,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: KangColors.slate),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.change,
                  style: TextStyle(
                    color: changeColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.marketCap,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onAdd != null)
                SizedBox(
                  width: 40,
                  child: canAdd
                      ? IconButton(
                          tooltip: 'Watchlist 추가',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.add_circle_outline_rounded,
                            color: color,
                            size: 20,
                          ),
                          onPressed: onAdd,
                        )
                      : Icon(
                          Icons.check_circle_rounded,
                          color: color.withValues(alpha: 0.55),
                          size: 18,
                        ),
                ),
              SizedBox(
                width: 76,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusPill(text: item.market, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTradingWatchlistCards extends StatelessWidget {
  const _StockTradingWatchlistCards({
    required this.items,
    required this.selectedSymbol,
    required this.color,
    required this.currentWatchlistSymbols,
    required this.onSymbolSelected,
    this.onSymbolAdded,
  });

  final List<_StockTradingWatchlistItem> items;
  final String selectedSymbol;
  final Color color;
  final Set<String> currentWatchlistSymbols;
  final ValueChanged<String> onSymbolSelected;
  final ValueChanged<_StockTradingWatchlistItem>? onSymbolAdded;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = item.symbol == selectedSymbol;
        final canAdd =
            onSymbolAdded != null &&
            !currentWatchlistSymbols.contains(item.symbol.trim().toUpperCase());
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSymbolSelected(item.symbol),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.085)
                    : _stockSurfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? color.withValues(alpha: 0.3)
                      : _stockPanelBorderColor.withValues(alpha: 0.9),
                ),
                boxShadow: selected ? _stockInnerShadow : null,
              ),
              child: Row(
                children: [
                  _StockTradingSymbolAvatar(
                    symbol: item.symbol,
                    name: item.name,
                    logoAsset: item.logoAsset,
                    logoUrl: item.logoUrl,
                    selected: selected,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: KangColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.symbol,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: KangColors.slate),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (onSymbolAdded != null) ...[
                    IconButton(
                      tooltip: canAdd ? 'Watchlist 추가' : '이미 추가됨',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        canAdd
                            ? Icons.add_circle_outline_rounded
                            : Icons.check_circle_rounded,
                        color: color,
                        size: 20,
                      ),
                      onPressed: canAdd ? () => onSymbolAdded!(item) : null,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.price,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KangColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.change,
                        style: TextStyle(
                          color: _stockChangeColor(item.changeValue),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemCount: items.length,
    );
  }
}

class _StockTradingSymbolAvatar extends StatelessWidget {
  const _StockTradingSymbolAvatar({
    required this.symbol,
    required this.name,
    required this.logoAsset,
    required this.logoUrl,
    required this.selected,
    required this.color,
  });

  final String symbol;
  final String name;
  final String logoAsset;
  final String logoUrl;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trimmedLogoAsset = logoAsset.trim();
    final trimmedLogoUrl = logoUrl.trim();
    final brandSpec = _stockBrandMarkSpecFor(symbol, name);
    if (brandSpec != null) {
      return _StockTradingPremiumSymbolAvatar(
        spec: brandSpec,
        selected: selected,
        color: color,
      );
    }

    final fallback = _StockTradingPremiumSymbolAvatar(
      spec: _stockFallbackBrandMarkSpec(symbol, name),
      selected: selected,
      color: color,
    );

    if (trimmedLogoAsset.isEmpty && trimmedLogoUrl.isEmpty) {
      return fallback;
    }

    final image = trimmedLogoAsset.isEmpty
        ? Image.network(
            trimmedLogoUrl,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            semanticLabel: '$name logo',
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.asset(
            trimmedLogoAsset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            semanticLabel: '$name logo',
            errorBuilder: (_, _, _) => fallback,
          );

    return _StockTradingLogoAvatarFrame(
      symbol: symbol,
      selected: selected,
      color: color,
      child: image,
    );
  }
}

class _StockTradingLogoAvatarFrame extends StatelessWidget {
  const _StockTradingLogoAvatarFrame({
    required this.symbol,
    required this.selected,
    required this.color,
    required this.child,
  });

  final String symbol;
  final bool selected;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? color
              : _stockAvatarColor(symbol).withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: KangColors.ink.withValues(alpha: selected ? 0.13 : 0.08),
            blurRadius: selected ? 14 : 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _StockTradingPremiumSymbolAvatar extends StatelessWidget {
  const _StockTradingPremiumSymbolAvatar({
    required this.spec,
    required this.selected,
    required this.color,
  });

  final _StockTradingBrandMarkSpec spec;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? color : spec.background.withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: spec.background.withValues(alpha: selected ? 0.26 : 0.16),
            blurRadius: selected ? 14 : 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(color: spec.background),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 13,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              if (spec.accent != null)
                Positioned(
                  left: 5,
                  right: 5,
                  bottom: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: spec.accent!.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const SizedBox(height: 2),
                  ),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      spec.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: spec.foreground,
                        fontSize: spec.label.length > 2
                            ? 9.5
                            : spec.label.length == 2
                            ? 12
                            : 17,
                        height: 1,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTradingBrandMarkSpec {
  const _StockTradingBrandMarkSpec({
    required this.label,
    required this.background,
    required this.foreground,
    this.accent,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? accent;
}

const Map<String, _StockTradingBrandMarkSpec> _stockBrandMarkSpecs = {
  '005930': _StockTradingBrandMarkSpec(
    label: 'S',
    background: Color(0xFF1476FF),
    foreground: Colors.white,
    accent: Color(0xFFBFE0FF),
  ),
  '000660': _StockTradingBrandMarkSpec(
    label: 'SK',
    background: Color(0xFFFF4B2B),
    foreground: Colors.white,
    accent: Color(0xFFFFD43B),
  ),
  '035420': _StockTradingBrandMarkSpec(
    label: 'N',
    background: Color(0xFF03C75A),
    foreground: Colors.white,
    accent: Color(0xFFA7F3D0),
  ),
  '035720': _StockTradingBrandMarkSpec(
    label: 'k',
    background: Color(0xFFFFD43B),
    foreground: Color(0xFF18181B),
    accent: Color(0xFF3A2929),
  ),
  '068270': _StockTradingBrandMarkSpec(
    label: 'C',
    background: Color(0xFF16A34A),
    foreground: Colors.white,
    accent: Color(0xFFBBF7D0),
  ),
  '005380': _StockTradingBrandMarkSpec(
    label: 'H',
    background: Color(0xFF0B2F6B),
    foreground: Colors.white,
    accent: Color(0xFF9CC9FF),
  ),
  '051910': _StockTradingBrandMarkSpec(
    label: 'LG',
    background: Color(0xFFC2185B),
    foreground: Colors.white,
    accent: Color(0xFFFFB3C7),
  ),
  '006400': _StockTradingBrandMarkSpec(
    label: 'SDI',
    background: Color(0xFF1D4ED8),
    foreground: Colors.white,
    accent: Color(0xFFBFDBFE),
  ),
  '207940': _StockTradingBrandMarkSpec(
    label: 'BIO',
    background: Color(0xFF0F766E),
    foreground: Colors.white,
    accent: Color(0xFF99F6E4),
  ),
  '105560': _StockTradingBrandMarkSpec(
    label: 'KB',
    background: Color(0xFFFFC400),
    foreground: Color(0xFF1F2937),
    accent: Color(0xFF6B7280),
  ),
  'NVDA': _StockTradingBrandMarkSpec(
    label: 'NV',
    background: Color(0xFF76B900),
    foreground: Colors.white,
    accent: Color(0xFFD9F99D),
  ),
  'AAPL': _StockTradingBrandMarkSpec(
    label: 'A',
    background: Color(0xFF111827),
    foreground: Colors.white,
    accent: Color(0xFFE5E7EB),
  ),
  'MSFT': _StockTradingBrandMarkSpec(
    label: 'MS',
    background: Color(0xFF2563EB),
    foreground: Colors.white,
    accent: Color(0xFFFFB900),
  ),
  'TSLA': _StockTradingBrandMarkSpec(
    label: 'T',
    background: Color(0xFFE82127),
    foreground: Colors.white,
    accent: Color(0xFFFFCDD2),
  ),
};

_StockTradingBrandMarkSpec? _stockBrandMarkSpecFor(String symbol, String name) {
  final normalizedSymbol = symbol.trim().toUpperCase();
  final direct = _stockBrandMarkSpecs[normalizedSymbol];
  if (direct != null) {
    return direct;
  }

  final normalizedName = name.trim().toLowerCase();
  if (normalizedName.contains('samsung')) {
    return _stockBrandMarkSpecs['005930'];
  }
  if (normalizedName.contains('naver')) {
    return _stockBrandMarkSpecs['035420'];
  }
  if (normalizedName.contains('kakao')) {
    return _stockBrandMarkSpecs['035720'];
  }
  if (normalizedName.contains('nvidia')) {
    return _stockBrandMarkSpecs['NVDA'];
  }
  if (normalizedName.contains('apple')) {
    return _stockBrandMarkSpecs['AAPL'];
  }
  if (normalizedName.contains('microsoft')) {
    return _stockBrandMarkSpecs['MSFT'];
  }
  if (normalizedName.contains('tesla')) {
    return _stockBrandMarkSpecs['TSLA'];
  }
  return null;
}

_StockTradingBrandMarkSpec _stockFallbackBrandMarkSpec(
  String symbol,
  String name,
) {
  final source = name.trim().isNotEmpty ? name.trim() : symbol.trim();
  final label = _stockBrandMarkLabel(source);
  final background = _stockAvatarColor(symbol);
  return _StockTradingBrandMarkSpec(
    label: label,
    background: background,
    foreground: Colors.white,
    accent: Colors.white.withValues(alpha: 0.72),
  );
}

String _stockBrandMarkLabel(String source) {
  final ascii = RegExp(r'[A-Za-z0-9]+')
      .allMatches(source)
      .map((match) {
        return match.group(0) ?? '';
      })
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (ascii.isNotEmpty) {
    final joined = ascii.join('');
    return joined.substring(0, math.min(3, joined.length)).toUpperCase();
  }
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first.toUpperCase();
}

class _StockTradingChartInterval {
  const _StockTradingChartInterval({
    required this.label,
    required this.bucketMinutes,
    this.sourceInterval = '1m',
    this.showChevron = false,
  });

  final String label;
  final int bucketMinutes;
  final String sourceInterval;
  final bool showChevron;

  static const fiveMinutes = _StockTradingChartInterval(
    label: '5m',
    bucketMinutes: 5,
  );
  static const tenMinutes = _StockTradingChartInterval(
    label: '10m',
    bucketMinutes: 10,
  );
  static const thirtyMinutes = _StockTradingChartInterval(
    label: '30m',
    bucketMinutes: 30,
  );
  static const oneHour = _StockTradingChartInterval(
    label: '1h',
    bucketMinutes: 60,
  );
  static const fourHours = _StockTradingChartInterval(
    label: '4h',
    bucketMinutes: 240,
  );
  static const day = _StockTradingChartInterval(
    label: 'D',
    bucketMinutes: 1,
    sourceInterval: '1d',
  );
  static const week = _StockTradingChartInterval(
    label: 'W',
    bucketMinutes: 10080,
    sourceInterval: '1d',
  );
  static const month = _StockTradingChartInterval(
    label: 'M',
    bucketMinutes: 43200,
    sourceInterval: '1d',
  );
  static const year = _StockTradingChartInterval(
    label: 'Y',
    bucketMinutes: 525600,
    sourceInterval: '1d',
    showChevron: true,
  );

  static const values = [
    fiveMinutes,
    tenMinutes,
    thirtyMinutes,
    oneHour,
    fourHours,
    day,
    week,
    month,
    year,
  ];
}

class _StockTradingStrategyPanel extends StatefulWidget {
  const _StockTradingStrategyPanel({
    required this.config,
    required this.marketCode,
    required this.selectedSymbol,
    required this.quotes,
    required this.dashboard,
    required this.activeDashboard,
    required this.quote,
    required this.loading,
    required this.error,
    required this.onSymbolSelected,
  });

  final _StockTradingMarketConfig config;
  final String marketCode;
  final String selectedSymbol;
  final List<TossStockQuote> quotes;
  final TossStockDashboard? dashboard;
  final TossStockDashboard? activeDashboard;
  final TossStockQuote? quote;
  final bool loading;
  final String? error;
  final ValueChanged<String> onSymbolSelected;

  @override
  State<_StockTradingStrategyPanel> createState() =>
      _StockTradingStrategyPanelState();
}

class _StockTradingStrategyPanelState
    extends State<_StockTradingStrategyPanel> {
  var _selectedPresetId = _StockTradingStrategyPreset.balanced.id;
  var _riskBudget = 0.62;

  @override
  Widget build(BuildContext context) {
    final preset = _StockTradingStrategyPreset.byId(_selectedPresetId);
    final candidates = _stockStrategyCandidates(widget.quotes, preset);
    final headlineCandidate = candidates.isEmpty ? null : candidates.first;
    final breadth = _stockStrategyBreadth(candidates);
    final averageScore = _stockStrategyAverage(
      candidates.map((candidate) => candidate.score),
    );
    final marketRegime = _stockStrategyMarketRegime(
      widget.activeDashboard?.candles ?? const <TossCandle>[],
      breadth: breadth,
    );
    final loading = widget.loading && candidates.isEmpty;

    return _StockTradingPanel(
      title: '전략 투자',
      icon: Icons.auto_graph_rounded,
      color: widget.config.color,
      trailing: _StatusPill(text: preset.label, color: widget.config.color),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final metricWidth = compact
              ? math.max(138.0, (constraints.maxWidth - 38) / 2)
              : math.max(142.0, (constraints.maxWidth - 72) / 4);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StockTradingStrategyHeader(
                  color: widget.config.color,
                  preset: preset,
                  marketCode: widget.marketCode,
                  selectedCandidate: headlineCandidate,
                  marketRegime: marketRegime,
                  onSymbolSelected: widget.onSymbolSelected,
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white;
                        }
                        return KangColors.slate;
                      }),
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return widget.config.color;
                        }
                        return Colors.white;
                      }),
                    ),
                    segments: [
                      for (final item in _StockTradingStrategyPreset.values)
                        ButtonSegment<String>(
                          value: item.id,
                          icon: Icon(item.icon, size: 16),
                          label: Text(item.label),
                        ),
                    ],
                    selected: {_selectedPresetId},
                    onSelectionChanged: (selection) {
                      final next = selection.isEmpty ? null : selection.first;
                      if (next != null) {
                        setState(() => _selectedPresetId = next);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: metricWidth,
                      child: _StockTradingStrategyMetricCard(
                        icon: Icons.model_training_rounded,
                        label: '모델 상태',
                        value: loading ? '계산 중' : marketRegime.label,
                        color: marketRegime.color,
                      ),
                    ),
                    SizedBox(
                      width: metricWidth,
                      child: _StockTradingStrategyMetricCard(
                        icon: Icons.format_list_numbered_rounded,
                        label: '후보 종목',
                        value: '${candidates.length}개',
                        color: widget.config.color,
                      ),
                    ),
                    SizedBox(
                      width: metricWidth,
                      child: _StockTradingStrategyMetricCard(
                        icon: Icons.speed_rounded,
                        label: '평균 점수',
                        value: candidates.isEmpty
                            ? '-'
                            : averageScore.toStringAsFixed(1),
                        color: _stockStrategyScoreColor(averageScore),
                      ),
                    ),
                    SizedBox(
                      width: metricWidth,
                      child: _StockTradingStrategyMetricCard(
                        icon: Icons.health_and_safety_outlined,
                        label: '리스크 예산',
                        value: '${(_riskBudget * 100).round()}%',
                        color: const Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (widget.error != null && candidates.isEmpty)
                  _StockTradingStrategyStatus(
                    icon: Icons.error_outline_rounded,
                    title: '전략 데이터를 불러오지 못했습니다.',
                    message: widget.error!,
                    color: _stockFallColor,
                  )
                else if (loading)
                  _StockTradingStrategyStatus(
                    icon: Icons.cloud_sync_rounded,
                    title: '전략 신호를 계산하고 있습니다.',
                    message: widget.marketCode,
                    color: widget.config.color,
                  )
                else if (candidates.isEmpty)
                  _StockTradingStrategyStatus(
                    icon: Icons.manage_search_rounded,
                    title: '전략 후보가 없습니다.',
                    message: 'Watchlist에 종목을 추가하면 전략 랭킹이 생성됩니다.',
                    color: widget.config.color,
                  )
                else if (compact)
                  Column(
                    children: [
                      _StockTradingStrategyRankingPanel(
                        color: widget.config.color,
                        candidates: candidates,
                        selectedSymbol: widget.selectedSymbol,
                        onSymbolSelected: widget.onSymbolSelected,
                      ),
                      const SizedBox(height: 12),
                      _StockTradingStrategyAllocationPanel(
                        color: widget.config.color,
                        candidates: candidates,
                        riskBudget: _riskBudget,
                      ),
                      const SizedBox(height: 12),
                      _StockTradingStrategyFactorPanel(
                        candidates: candidates,
                        preset: preset,
                      ),
                      const SizedBox(height: 12),
                      _StockTradingStrategyRiskPanel(
                        color: widget.config.color,
                        riskBudget: _riskBudget,
                        candidates: candidates,
                        onChanged: (value) =>
                            setState(() => _riskBudget = value),
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: _StockTradingStrategyRankingPanel(
                          color: widget.config.color,
                          candidates: candidates,
                          selectedSymbol: widget.selectedSymbol,
                          onSymbolSelected: widget.onSymbolSelected,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            _StockTradingStrategyAllocationPanel(
                              color: widget.config.color,
                              candidates: candidates,
                              riskBudget: _riskBudget,
                            ),
                            const SizedBox(height: 12),
                            _StockTradingStrategyFactorPanel(
                              candidates: candidates,
                              preset: preset,
                            ),
                            const SizedBox(height: 12),
                            _StockTradingStrategyRiskPanel(
                              color: widget.config.color,
                              riskBudget: _riskBudget,
                              candidates: candidates,
                              onChanged: (value) =>
                                  setState(() => _riskBudget = value),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StockTradingStrategyHeader extends StatelessWidget {
  const _StockTradingStrategyHeader({
    required this.color,
    required this.preset,
    required this.marketCode,
    required this.selectedCandidate,
    required this.marketRegime,
    required this.onSymbolSelected,
  });

  final Color color;
  final _StockTradingStrategyPreset preset;
  final String marketCode;
  final _StockTradingStrategyCandidate? selectedCandidate;
  final _StockTradingStrategyRegime marketRegime;
  final ValueChanged<String> onSymbolSelected;

  @override
  Widget build(BuildContext context) {
    final candidate = selectedCandidate;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: _stockPanelShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.32)),
                    ),
                    child: Icon(preset.icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Strategy Lab',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${preset.label} · $marketCode',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StockTradingStrategyDarkPill(
                    text: marketRegime.label,
                    color: marketRegime.color,
                  ),
                  _StockTradingStrategyDarkPill(
                    text: candidate?.signal ?? '신호 대기',
                    color: candidate == null
                        ? KangColors.slate
                        : _stockStrategyScoreColor(candidate.score),
                  ),
                ],
              ),
            ],
          );

          final ticket = Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: candidate == null
                ? const Text(
                    '선택 종목 없음',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${candidate.symbol} ${candidate.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            candidate.score.toStringAsFixed(1),
                            style: TextStyle(
                              color: _stockStrategyScoreColor(candidate.score),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      _StockTradingStrategyScoreBar(
                        value: candidate.score,
                        color: _stockStrategyScoreColor(candidate.score),
                        trackColor: Colors.white.withValues(alpha: 0.14),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              candidate.price,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD8DEE9),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: color,
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.input_rounded, size: 16),
                            label: const Text('주문 반영'),
                            onPressed: () => onSymbolSelected(candidate.symbol),
                          ),
                        ],
                      ),
                    ],
                  ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, const SizedBox(height: 12), ticket],
            );
          }

          return Row(
            children: [
              Expanded(child: summary),
              const SizedBox(width: 14),
              SizedBox(width: 310, child: ticket),
            ],
          );
        },
      ),
    );
  }
}

class _StockTradingStrategyRankingPanel extends StatelessWidget {
  const _StockTradingStrategyRankingPanel({
    required this.color,
    required this.candidates,
    required this.selectedSymbol,
    required this.onSymbolSelected,
  });

  final Color color;
  final List<_StockTradingStrategyCandidate> candidates;
  final String selectedSymbol;
  final ValueChanged<String> onSymbolSelected;

  @override
  Widget build(BuildContext context) {
    return _StockTradingStrategySurface(
      title: '전략 랭킹',
      icon: Icons.leaderboard_rounded,
      trailing: '${candidates.length}개',
      child: Column(
        children: [
          for (final candidate in candidates.take(8)) ...[
            _StockTradingStrategyCandidateTile(
              color: color,
              candidate: candidate,
              selected: candidate.symbol == selectedSymbol,
              onSelected: () => onSymbolSelected(candidate.symbol),
            ),
            if (candidate != candidates.take(8).last)
              const Divider(height: 1, color: _stockPanelBorderColor),
          ],
        ],
      ),
    );
  }
}

class _StockTradingStrategyCandidateTile extends StatelessWidget {
  const _StockTradingStrategyCandidateTile({
    required this.color,
    required this.candidate,
    required this.selected,
    required this.onSelected,
  });

  final Color color;
  final _StockTradingStrategyCandidate candidate;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scoreColor = _stockStrategyScoreColor(candidate.score);
    return Material(
      color: selected ? color.withValues(alpha: 0.06) : Colors.transparent,
      child: InkWell(
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _StockTradingSymbolAvatar(
                symbol: candidate.symbol,
                name: candidate.name,
                logoAsset: '',
                logoUrl: _stockTradingLogoUrlForSymbol(candidate.symbol),
                selected: selected,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${candidate.symbol} · ${candidate.market}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: KangColors.slate,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          candidate.score.toStringAsFixed(1),
                          style: TextStyle(
                            color: scoreColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            candidate.signal,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: KangColors.slate,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _StockTradingStrategyScoreBar(
                      value: candidate.score,
                      color: scoreColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      candidate.price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      candidate.changeLabel,
                      style: TextStyle(
                        color: _stockChangeColor(candidate.changePercent),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '주문 패널에 반영',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.input_rounded, color: color, size: 20),
                  onPressed: onSelected,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTradingStrategyAllocationPanel extends StatelessWidget {
  const _StockTradingStrategyAllocationPanel({
    required this.color,
    required this.candidates,
    required this.riskBudget,
  });

  final Color color;
  final List<_StockTradingStrategyCandidate> candidates;
  final double riskBudget;

  @override
  Widget build(BuildContext context) {
    final allocations = _stockStrategyAllocations(candidates, riskBudget);
    final cashWeight = math.max(
      0.0,
      100 - allocations.fold<double>(0, (sum, item) => sum + item.$2),
    );
    return _StockTradingStrategySurface(
      title: '목표 배분',
      icon: Icons.donut_small_rounded,
      trailing: '${allocations.length}종목',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            for (final allocation in allocations) ...[
              _StockTradingStrategyAllocationRow(
                candidate: allocation.$1,
                weight: allocation.$2,
                color: color,
              ),
              const SizedBox(height: 9),
            ],
            _StockTradingStrategyAllocationRow(
              label: '현금',
              weight: cashWeight,
              color: KangColors.slate,
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTradingStrategyAllocationRow extends StatelessWidget {
  const _StockTradingStrategyAllocationRow({
    required this.weight,
    required this.color,
    this.candidate,
    this.label,
  });

  final _StockTradingStrategyCandidate? candidate;
  final String? label;
  final double weight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final title = label ?? candidate?.symbol ?? '-';
    final subtitle = candidate?.name ?? '대기 자금';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KangColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '${weight.toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KangColors.slate,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        _StockTradingStrategyScoreBar(
          value: weight,
          maxValue: 100,
          color: color,
        ),
      ],
    );
  }
}

class _StockTradingStrategyFactorPanel extends StatelessWidget {
  const _StockTradingStrategyFactorPanel({
    required this.candidates,
    required this.preset,
  });

  final List<_StockTradingStrategyCandidate> candidates;
  final _StockTradingStrategyPreset preset;

  @override
  Widget build(BuildContext context) {
    final top = candidates.take(5).toList(growable: false);
    final source = top.isEmpty ? candidates : top;
    final factors = [
      ('모멘텀', _stockStrategyAverage(source.map((item) => item.momentum))),
      ('퀄리티', _stockStrategyAverage(source.map((item) => item.quality))),
      ('안정성', _stockStrategyAverage(source.map((item) => item.stability))),
      ('유동성', _stockStrategyAverage(source.map((item) => item.liquidity))),
    ];
    return _StockTradingStrategySurface(
      title: '팩터 노출',
      icon: Icons.radar_rounded,
      trailing: preset.label,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            for (final factor in factors) ...[
              _StockTradingStrategyFactorRow(
                label: factor.$1,
                value: factor.$2,
                color: _stockStrategyScoreColor(factor.$2),
              ),
              if (factor != factors.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _StockTradingStrategyFactorRow extends StatelessWidget {
  const _StockTradingStrategyFactorRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            label,
            style: const TextStyle(
              color: KangColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: _StockTradingStrategyScoreBar(value: value, color: color),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 38,
          child: Text(
            value.toStringAsFixed(0),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _StockTradingStrategyRiskPanel extends StatelessWidget {
  const _StockTradingStrategyRiskPanel({
    required this.color,
    required this.riskBudget,
    required this.candidates,
    required this.onChanged,
  });

  final Color color;
  final double riskBudget;
  final List<_StockTradingStrategyCandidate> candidates;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final averageRisk = _stockStrategyAverage(
      candidates.map((candidate) => candidate.risk),
    );
    final maxPosition = (18 * riskBudget + 4).clamp(6, 22).toDouble();
    return _StockTradingStrategySurface(
      title: '리스크 예산',
      icon: Icons.shield_outlined,
      trailing: '${(riskBudget * 100).round()}%',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Slider(
              value: riskBudget,
              min: 0.25,
              max: 1,
              divisions: 15,
              activeColor: color,
              label: '${(riskBudget * 100).round()}%',
              onChanged: onChanged,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _StockTradingStrategyMiniMetric(
                    label: '평균 위험',
                    value: averageRisk.toStringAsFixed(1),
                    color: _stockStrategyRiskColor(averageRisk),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StockTradingStrategyMiniMetric(
                    label: '최대 비중',
                    value: '${maxPosition.toStringAsFixed(1)}%',
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTradingStrategyMetricCard extends StatelessWidget {
  const _StockTradingStrategyMetricCard({
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
    return Container(
      height: 76,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
        boxShadow: _stockInnerShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingStrategyMiniMetric extends StatelessWidget {
  const _StockTradingStrategyMiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _stockSurfaceMutedColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: KangColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingStrategySurface extends StatelessWidget {
  const _StockTradingStrategySurface({
    required this.title,
    required this.icon,
    required this.trailing,
    required this.child,
  });

  final String title;
  final IconData icon;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
        boxShadow: _stockInnerShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: _stockPanelHeaderColor,
              border: Border(bottom: BorderSide(color: _stockPanelBorderColor)),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: KangColors.slate),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  trailing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _StockTradingStrategyStatus extends StatelessWidget {
  const _StockTradingStrategyStatus({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: KangColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
          ),
        ],
      ),
    );
  }
}

class _StockTradingStrategyScoreBar extends StatelessWidget {
  const _StockTradingStrategyScoreBar({
    required this.value,
    required this.color,
    this.maxValue = 100,
    this.trackColor = const Color(0xFFE8EDF5),
  });

  final double value;
  final double maxValue;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 7,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: trackColor)),
            FractionallySizedBox(
              widthFactor: ratio,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTradingStrategyDarkPill extends StatelessWidget {
  const _StockTradingStrategyDarkPill({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StockTradingStrategyPreset {
  const _StockTradingStrategyPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.momentumWeight,
    required this.qualityWeight,
    required this.stabilityWeight,
    required this.liquidityWeight,
  });

  final String id;
  final String label;
  final IconData icon;
  final double momentumWeight;
  final double qualityWeight;
  final double stabilityWeight;
  final double liquidityWeight;

  static const balanced = _StockTradingStrategyPreset(
    id: 'balanced',
    label: '밸런스',
    icon: Icons.hub_outlined,
    momentumWeight: 0.30,
    qualityWeight: 0.28,
    stabilityWeight: 0.27,
    liquidityWeight: 0.15,
  );
  static const momentum = _StockTradingStrategyPreset(
    id: 'momentum',
    label: '모멘텀',
    icon: Icons.trending_up_rounded,
    momentumWeight: 0.56,
    qualityWeight: 0.16,
    stabilityWeight: 0.14,
    liquidityWeight: 0.14,
  );
  static const quality = _StockTradingStrategyPreset(
    id: 'quality',
    label: '퀄리티',
    icon: Icons.verified_outlined,
    momentumWeight: 0.18,
    qualityWeight: 0.47,
    stabilityWeight: 0.22,
    liquidityWeight: 0.13,
  );
  static const lowVol = _StockTradingStrategyPreset(
    id: 'low-vol',
    label: '저변동',
    icon: Icons.show_chart_rounded,
    momentumWeight: 0.16,
    qualityWeight: 0.20,
    stabilityWeight: 0.50,
    liquidityWeight: 0.14,
  );

  static const values = [balanced, momentum, quality, lowVol];

  static _StockTradingStrategyPreset byId(String id) {
    for (final preset in values) {
      if (preset.id == id) {
        return preset;
      }
    }
    return balanced;
  }
}

class _StockTradingStrategyCandidate {
  const _StockTradingStrategyCandidate({
    required this.symbol,
    required this.name,
    required this.market,
    required this.price,
    required this.changeLabel,
    required this.changePercent,
    required this.score,
    required this.momentum,
    required this.quality,
    required this.stability,
    required this.liquidity,
    required this.risk,
  });

  final String symbol;
  final String name;
  final String market;
  final String price;
  final String changeLabel;
  final double changePercent;
  final double score;
  final double momentum;
  final double quality;
  final double stability;
  final double liquidity;
  final double risk;

  String get signal {
    if (score >= 74) {
      return '강한 후보';
    }
    if (score >= 62) {
      return '편입 후보';
    }
    if (score >= 48) {
      return '관찰';
    }
    return '보류';
  }
}

class _StockTradingStrategyRegime {
  const _StockTradingStrategyRegime({required this.label, required this.color});

  final String label;
  final Color color;
}

List<_StockTradingStrategyCandidate> _stockStrategyCandidates(
  List<TossStockQuote> quotes,
  _StockTradingStrategyPreset preset,
) {
  final uniqueQuotes = <String, TossStockQuote>{};
  for (final quote in quotes) {
    final symbol = quote.symbol.trim().toUpperCase();
    if (symbol.isNotEmpty && quote.hasPrice) {
      uniqueQuotes[symbol] = quote;
    }
  }
  final usableQuotes = uniqueQuotes.values.toList(growable: false);
  if (usableQuotes.isEmpty) {
    return const <_StockTradingStrategyCandidate>[];
  }

  final capLogs = usableQuotes
      .map((quote) => quote.marketCapValue)
      .whereType<double>()
      .where((value) => value > 0)
      .map((value) => math.log(value) / math.ln10)
      .toList(growable: false);
  final minLogCap = capLogs.isEmpty ? 0.0 : capLogs.reduce(math.min);
  final maxLogCap = capLogs.isEmpty ? 0.0 : capLogs.reduce(math.max);

  final candidates = <_StockTradingStrategyCandidate>[];
  for (final quote in usableQuotes) {
    final symbol = quote.symbol.trim().toUpperCase();
    final name = quote.displayName.trim().isNotEmpty
        ? quote.displayName.trim()
        : symbol;
    final changePercent = quote.changePercentValue ?? 0;
    final momentum = (50 + changePercent * 7).clamp(0, 100).toDouble();
    final stability = (100 - changePercent.abs() * 8).clamp(0, 100).toDouble();
    final capValue = quote.marketCapValue;
    final liquidity = _stockStrategyLiquidityScore(
      capValue,
      minLogCap: minLogCap,
      maxLogCap: maxLogCap,
    );
    final quality = (liquidity * 0.42 + stability * 0.36 + momentum * 0.22)
        .clamp(0, 100)
        .toDouble();
    final score =
        momentum * preset.momentumWeight +
        quality * preset.qualityWeight +
        stability * preset.stabilityWeight +
        liquidity * preset.liquidityWeight;
    final market = quote.market.trim().toUpperCase();
    final currency = quote.currency.trim();
    final price = quote.lastPrice.trim().isEmpty
        ? '시세 대기'
        : '${_stockFormatNumber(quote.lastPrice)} $currency'.trim();
    final sign = changePercent > 0 ? '+' : '';
    candidates.add(
      _StockTradingStrategyCandidate(
        symbol: symbol,
        name: name,
        market: market.isEmpty ? 'KRX' : market,
        price: price,
        changeLabel: '$sign${changePercent.toStringAsFixed(2)}%',
        changePercent: changePercent,
        score: score.clamp(0, 100).toDouble(),
        momentum: momentum,
        quality: quality,
        stability: stability,
        liquidity: liquidity,
        risk: (100 - stability).clamp(0, 100).toDouble(),
      ),
    );
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  return List.unmodifiable(candidates);
}

double _stockStrategyLiquidityScore(
  double? marketCap, {
  required double minLogCap,
  required double maxLogCap,
}) {
  if (marketCap == null || marketCap <= 0) {
    return 45;
  }
  if ((maxLogCap - minLogCap).abs() < 0.0001) {
    return 70;
  }
  final logCap = math.log(marketCap) / math.ln10;
  return (40 + (logCap - minLogCap) / (maxLogCap - minLogCap) * 55)
      .clamp(0, 100)
      .toDouble();
}

double _stockStrategyBreadth(List<_StockTradingStrategyCandidate> candidates) {
  if (candidates.isEmpty) {
    return 0;
  }
  final positive = candidates
      .where((candidate) => candidate.changePercent > 0)
      .length;
  return positive / candidates.length;
}

double _stockStrategyAverage(Iterable<double> values) {
  var count = 0;
  var sum = 0.0;
  for (final value in values) {
    sum += value;
    count += 1;
  }
  return count == 0 ? 0 : sum / count;
}

_StockTradingStrategyRegime _stockStrategyMarketRegime(
  List<TossCandle> candles, {
  required double breadth,
}) {
  final closes = candles
      .map((candle) => candle.closePriceValue)
      .whereType<double>()
      .where((value) => value > 0)
      .toList(growable: false);
  var trend = 0.0;
  if (closes.length >= 2) {
    trend = (closes.last - closes.first) / closes.first * 100;
  }
  if (trend > 2 && breadth >= 0.45) {
    return const _StockTradingStrategyRegime(
      label: '상승 우위',
      color: _stockRiseColor,
    );
  }
  if (trend < -2 && breadth <= 0.35) {
    return const _StockTradingStrategyRegime(
      label: '방어 우위',
      color: _stockFallColor,
    );
  }
  return const _StockTradingStrategyRegime(
    label: '중립 균형',
    color: Color(0xFF0F766E),
  );
}

List<(_StockTradingStrategyCandidate, double)> _stockStrategyAllocations(
  List<_StockTradingStrategyCandidate> candidates,
  double riskBudget,
) {
  final selected = candidates.take(5).toList(growable: false);
  if (selected.isEmpty) {
    return const <(_StockTradingStrategyCandidate, double)>[];
  }
  final investedPercent = (46 + riskBudget * 46).clamp(0, 96).toDouble();
  final adjusted = [
    for (final candidate in selected)
      math.max(1.0, candidate.score * (1 - candidate.risk / 170)),
  ];
  final total = adjusted.fold<double>(0, (sum, value) => sum + value);
  return [
    for (var index = 0; index < selected.length; index++)
      (selected[index], investedPercent * adjusted[index] / total),
  ];
}

Color _stockStrategyScoreColor(double value) {
  if (value >= 72) {
    return const Color(0xFF0F766E);
  }
  if (value >= 58) {
    return const Color(0xFFE6A700);
  }
  if (value >= 44) {
    return _stockFallColor;
  }
  return KangColors.slate;
}

Color _stockStrategyRiskColor(double value) {
  if (value >= 58) {
    return _stockRiseColor;
  }
  if (value >= 35) {
    return const Color(0xFFE6A700);
  }
  return const Color(0xFF0F766E);
}

class _StockTradingChartWorkspace extends StatelessWidget {
  const _StockTradingChartWorkspace({
    required this.api,
    required this.config,
    required this.marketCode,
    required this.symbol,
    required this.dashboard,
    required this.quote,
    required this.loading,
    required this.error,
    required this.selectedInterval,
    required this.onIntervalChanged,
    required this.quotes,
    required this.onSymbolSelected,
  });

  final TossStockApi api;
  final _StockTradingMarketConfig config;
  final String marketCode;
  final String symbol;
  final TossStockDashboard? dashboard;
  final TossStockQuote? quote;
  final bool loading;
  final String? error;
  final _StockTradingChartInterval selectedInterval;
  final ValueChanged<_StockTradingChartInterval> onIntervalChanged;
  final List<TossStockQuote> quotes;
  final ValueChanged<String> onSymbolSelected;

  @override
  Widget build(BuildContext context) {
    final candles = _stockCandlesForInterval(
      dashboard?.candles ?? const <TossCandle>[],
      selectedInterval,
    );
    final profile = _StockTradingTechnicalProfile.from(
      candles,
      quote: quote,
      accentColor: config.color,
    );
    final movers = quotes.where((item) => item.hasPrice).toList()
      ..sort(
        (a, b) => (b.changePercentValue ?? -9999).compareTo(
          a.changePercentValue ?? -9999,
        ),
      );
    final chart = _StockTradingChartPlaceholder(
      api: api,
      color: config.color,
      marketCode: marketCode,
      symbol: symbol,
      dashboard: dashboard,
      quote: quote,
      loading: loading,
      selectedInterval: selectedInterval,
      onIntervalChanged: onIntervalChanged,
    );

    Widget timingSurface() {
      return _StockTradingWorkspaceSurface(
        title: '타이밍 보드',
        icon: Icons.speed_rounded,
        trailing: profile.signal,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth < 640
                  ? math.max(132.0, (constraints.maxWidth - 10) / 2)
                  : math.max(138.0, (constraints.maxWidth - 30) / 4);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.trending_up_rounded,
                      label: '추세',
                      value: profile.trendLabel,
                      color: profile.trendColor,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.timeline_rounded,
                      label: 'MA 정렬',
                      value: profile.maAlignment,
                      color: config.color,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.bar_chart_rounded,
                      label: '거래량',
                      value: profile.volumeRatio == null
                          ? '--'
                          : '${profile.volumeRatio!.toStringAsFixed(2)}배',
                      color:
                          profile.volumeRatio != null &&
                              profile.volumeRatio! >= 1.2
                          ? config.color
                          : KangColors.slate,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.open_in_full_rounded,
                      label: '가격 위치',
                      value: profile.rangePositionLabel,
                      color: config.color,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    Widget analysisColumn() {
      if (profile.candleCount == 0 && error?.trim().isNotEmpty == true) {
        return _StockTradingStrategyStatus(
          icon: Icons.error_outline_rounded,
          title: '차트 데이터를 불러오지 못했습니다.',
          message: error!,
          color: _stockFallColor,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StockTradingWorkspaceSurface(
            title: '기술적 신호',
            icon: Icons.analytics_outlined,
            trailing: loading ? '계산 중' : profile.signal,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          profile.trendLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: profile.trendColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        profile.score.toStringAsFixed(0),
                        style: TextStyle(
                          color: _stockStrategyScoreColor(profile.score),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _StockTradingStrategyScoreBar(
                    value: profile.score,
                    color: _stockStrategyScoreColor(profile.score),
                  ),
                  const SizedBox(height: 12),
                  _StockTradingAnalysisLine(
                    label: '20봉 모멘텀',
                    value: _stockPercentLabel(profile.momentum),
                    color: _stockChangeColor(profile.momentum),
                  ),
                  _StockTradingAnalysisLine(
                    label: '변동폭',
                    value: profile.volatility == null
                        ? '--'
                        : '${profile.volatility!.toStringAsFixed(2)}%',
                    color: KangColors.slate,
                  ),
                  _StockTradingAnalysisLine(
                    label: '거래량 강도',
                    value: profile.volumeRatio == null
                        ? '--'
                        : '${profile.volumeRatio!.toStringAsFixed(2)}배',
                    color:
                        profile.volumeRatio != null &&
                            profile.volumeRatio! >= 1.2
                        ? config.color
                        : KangColors.slate,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _StockTradingWorkspaceSurface(
            title: '이동평균',
            icon: Icons.show_chart_rounded,
            trailing: '${profile.candleCount}봉',
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _StockTradingAnalysisLine(
                    label: 'MA5',
                    value: _stockChartValue(profile.ma5),
                    color: _stockMaColor(
                      profile.lastPrice,
                      profile.ma5,
                      config.color,
                    ),
                  ),
                  _StockTradingAnalysisLine(
                    label: 'MA20',
                    value: _stockChartValue(profile.ma20),
                    color: _stockMaColor(
                      profile.lastPrice,
                      profile.ma20,
                      config.color,
                    ),
                  ),
                  _StockTradingAnalysisLine(
                    label: 'MA60',
                    value: _stockChartValue(profile.ma60),
                    color: _stockMaColor(
                      profile.lastPrice,
                      profile.ma60,
                      config.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _StockTradingWorkspaceSurface(
            title: '가격 위치',
            icon: Icons.stacked_line_chart_rounded,
            trailing: profile.rangePositionLabel,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StockTradingRangeBar(
                    value: profile.rangePosition,
                    color: config.color,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StockTradingMiniValue(
                          label: '저가권',
                          value: _stockChartValue(profile.lowPrice),
                          color: _stockFallColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StockTradingMiniValue(
                          label: '고가권',
                          value: _stockChartValue(profile.highPrice),
                          color: _stockRiseColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _StockTradingWorkspaceSurface(
            title: 'Watchlist 모멘텀',
            icon: Icons.leaderboard_rounded,
            trailing: '${movers.length}개',
            child: Column(
              children: [
                if (movers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      loading ? '시세를 불러오는 중입니다.' : '비교할 종목이 없습니다.',
                      style: const TextStyle(
                        color: KangColors.slate,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  for (
                    var index = 0;
                    index < math.min(5, movers.length);
                    index++
                  ) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onSymbolSelected(movers[index].symbol),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              _StockTradingSymbolAvatar(
                                symbol: movers[index].symbol,
                                name: movers[index].displayName,
                                logoAsset: '',
                                logoUrl: _stockTradingLogoUrlForSymbol(
                                  movers[index].symbol,
                                ),
                                selected: false,
                                color: config.color,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      movers[index].displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: KangColors.ink,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      movers[index].symbol,
                                      style: const TextStyle(
                                        color: KangColors.slate,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                movers[index].changePercentValue == null
                                    ? '--'
                                    : '${movers[index].changePercentValue!.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  color: _stockChangeColor(
                                    movers[index].changePercentValue,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (index < math.min(5, movers.length) - 1)
                      const Divider(height: 1, color: _stockPanelBorderColor),
                  ],
              ],
            ),
          ),
        ],
      );
    }

    return _StockTradingPanel(
      title: '차트 분석',
      icon: Icons.candlestick_chart_rounded,
      color: config.color,
      trailing: _StatusPill(
        text: _stockIntervalDisplayLabel(selectedInterval),
        color: config.color,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          if (compact) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  SizedBox(height: 360, child: chart),
                  const SizedBox(height: 12),
                  timingSurface(),
                  const SizedBox(height: 12),
                  analysisColumn(),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      Expanded(child: chart),
                      const SizedBox(height: 12),
                      timingSurface(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 330,
                  child: SingleChildScrollView(child: analysisColumn()),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StockTradingOrderWorkspace extends StatelessWidget {
  const _StockTradingOrderWorkspace({
    required this.config,
    required this.dashboard,
    required this.quote,
    required this.loading,
    required this.error,
  });

  final _StockTradingMarketConfig config;
  final TossStockDashboard? dashboard;
  final TossStockQuote? quote;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final readiness = _StockTradingOrderReadiness.from(
      dashboard: dashboard,
      quote: quote,
      currency: config.badge,
    );
    final orderbook = dashboard?.orderbook;
    final askRows =
        orderbook?.asks.take(8).toList().reversed.toList() ??
        const <TossOrderbookEntry>[];
    final bidRows =
        orderbook?.bids.take(8).toList() ?? const <TossOrderbookEntry>[];
    final maxVolume = [
      for (final row in askRows) _stockDoubleValue(row.volume) ?? 0,
      for (final row in bidRows) _stockDoubleValue(row.volume) ?? 0,
    ].fold<double>(0, math.max);

    Widget depthRow(String side, TossOrderbookEntry row, Color sideColor) {
      final volume = _stockDoubleValue(row.volume) ?? 0;
      final ratio = maxVolume <= 0 ? 0.0 : (volume / maxVolume).clamp(0.0, 1.0);
      return Container(
        height: 34,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: sideColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sideColor.withValues(alpha: 0.10)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: ratio,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: sideColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: Text(
                      side,
                      style: TextStyle(
                        color: sideColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _stockFormatNumber(row.price),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: sideColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 78,
                    child: Text(
                      _stockCompactNumber(volume),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: KangColors.slate,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget metricsSurface() {
      return _StockTradingWorkspaceSurface(
        title: '호가 실행력',
        icon: Icons.query_stats_rounded,
        trailing: readiness.spreadLabel,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth < 640
                  ? math.max(132.0, (constraints.maxWidth - 10) / 2)
                  : math.max(138.0, (constraints.maxWidth - 30) / 4);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.south_west_rounded,
                      label: '최우선 매수',
                      value: _stockChartValue(readiness.bestBid),
                      color: _stockBuyColor,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.north_east_rounded,
                      label: '최우선 매도',
                      value: _stockChartValue(readiness.bestAsk),
                      color: _stockSellColor,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.swap_vert_rounded,
                      label: '스프레드',
                      value: readiness.spreadLabel,
                      color: config.color,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.shopping_bag_outlined,
                      label: '가능 수량',
                      value: readiness.affordableQuantityLabel,
                      color: config.color,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    Widget depthSurface() {
      final hasRows = askRows.isNotEmpty || bidRows.isNotEmpty;
      return _StockTradingWorkspaceSurface(
        title: '호가 래더',
        icon: Icons.view_week_rounded,
        trailing: orderbook?.symbol.trim().isNotEmpty == true
            ? orderbook!.symbol
            : '실시간',
        expandChild: true,
        child: hasRows
            ? ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final row in askRows)
                    depthRow('매도', row, _stockSellColor),
                  const SizedBox(height: 8),
                  Divider(
                    height: 1,
                    color: config.color.withValues(alpha: 0.24),
                  ),
                  const SizedBox(height: 8),
                  for (final row in bidRows)
                    depthRow('매수', row, _stockBuyColor),
                ],
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    loading ? '호가를 불러오는 중입니다.' : error ?? '호가 데이터 대기',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: KangColors.slate,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
      );
    }

    Widget scenarioSurface() {
      final scenarios = [0.1, 0.25, 0.5, 1.0];
      return _StockTradingWorkspaceSurface(
        title: '주문 규모 시뮬레이션',
        icon: Icons.calculate_outlined,
        trailing: readiness.currency,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (final ratio in scenarios) ...[
                Builder(
                  builder: (context) {
                    final quantity =
                        readiness.buyingPower == null ||
                            readiness.referencePrice == null
                        ? null
                        : (readiness.buyingPower! *
                                  ratio /
                                  readiness.referencePrice!)
                              .floor();
                    final referencePrice = readiness.referencePrice;
                    final amount = quantity == null || referencePrice == null
                        ? null
                        : quantity * referencePrice;
                    final amountLabel = referencePrice == null
                        ? '금액 계산 대기'
                        : quantity == 0
                        ? '최소 1주 ${_stockChartValue(referencePrice)} ${readiness.currency} 필요'
                        : '${_stockChartValue(amount)} ${readiness.currency}';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${(ratio * 100).round()}%',
                              style: TextStyle(
                                color: config.color,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StockTradingStrategyScoreBar(
                                value: ratio * 100,
                                color: config.color,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              quantity == null
                                  ? '--주'
                                  : '${_stockFormatNumber('$quantity')}주',
                              style: const TextStyle(
                                color: KangColors.ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            amountLabel,
                            style: const TextStyle(
                              color: KangColors.slate,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (ratio != scenarios.last) const SizedBox(height: 9),
              ],
            ],
          ),
        ),
      );
    }

    Widget readinessSurface() {
      final checks = [
        ('실전 주문 권한', readiness.tradingAvailable),
        ('현재가 수신', readiness.referencePrice != null),
        ('호가 수신', readiness.hasOrderbook),
        ('주문가능금액 조회', readiness.buyingPower != null),
        ('최소 1주 가능', readiness.canBuyMinimum),
      ];
      return _StockTradingWorkspaceSurface(
        title: '주문 전 체크',
        icon: Icons.fact_check_outlined,
        trailing: loading ? '확인 중' : readiness.readyLabel,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (final check in checks) ...[
                Row(
                  children: [
                    Icon(
                      check.$2
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                      color: check.$2 ? config.color : KangColors.slate,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        check.$1,
                        style: const TextStyle(
                          color: KangColors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      check.$2 ? '확인' : '대기',
                      style: TextStyle(
                        color: check.$2 ? config.color : KangColors.slate,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                if (check != checks.last) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
    }

    final sideColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        scenarioSurface(),
        const SizedBox(height: 12),
        readinessSurface(),
        const SizedBox(height: 12),
        _StockTradingWorkspaceSurface(
          title: '가격 기준',
          icon: Icons.tune_rounded,
          trailing: readiness.currency,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _StockTradingAnalysisLine(
                  label: '현재가',
                  value: _stockChartValue(readiness.lastPrice),
                  color: KangColors.ink,
                ),
                _StockTradingAnalysisLine(
                  label: '매수 대기',
                  value: _stockChartValue(readiness.bestBid),
                  color: _stockBuyColor,
                ),
                _StockTradingAnalysisLine(
                  label: '매도 대기',
                  value: _stockChartValue(readiness.bestAsk),
                  color: _stockSellColor,
                ),
                _StockTradingAnalysisLine(
                  label: '호가 불균형',
                  value: readiness.imbalanceLabel,
                  color: readiness.imbalanceColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return _StockTradingPanel(
      title: '주문 준비',
      icon: Icons.price_check_rounded,
      color: config.color,
      trailing: _StatusPill(text: config.badge, color: config.color),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          if (compact) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  metricsSurface(),
                  const SizedBox(height: 12),
                  SizedBox(height: 420, child: depthSurface()),
                  const SizedBox(height: 12),
                  sideColumn,
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      metricsSurface(),
                      const SizedBox(height: 12),
                      Expanded(child: depthSurface()),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 330,
                  child: SingleChildScrollView(child: sideColumn),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StockTradingExecutionWorkspace extends StatelessWidget {
  const _StockTradingExecutionWorkspace({
    required this.config,
    required this.dashboard,
    required this.loading,
    required this.error,
  });

  final _StockTradingMarketConfig config;
  final TossStockDashboard? dashboard;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final profile = _StockTradingExecutionProfile.from(
      dashboard,
      currency: config.badge,
    );

    Widget metricsSurface() {
      return _StockTradingWorkspaceSurface(
        title: '계좌 스냅샷',
        icon: Icons.account_balance_wallet_outlined,
        trailing: loading ? '조회 중' : profile.accountLabel,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth < 640
                  ? math.max(132.0, (constraints.maxWidth - 10) / 2)
                  : math.max(138.0, (constraints.maxWidth - 30) / 4);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.pie_chart_outline_rounded,
                      label: '추정자산',
                      value: profile.estimatedAssetLabel,
                      color: config.color,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.show_chart_rounded,
                      label: '평가손익',
                      value: profile.profitLossLabel,
                      color: _stockChangeColor(profile.totalProfitLoss),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.pending_actions_outlined,
                      label: '주문가능',
                      value: profile.buyingPowerLabel,
                      color: config.color,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _StockTradingStrategyMetricCard(
                      icon: Icons.check_circle_outline_rounded,
                      label: '미체결',
                      value: '${profile.openOrders.length}건',
                      color: config.color,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    Widget holdingRow(TossHolding holding) {
      final profit = _stockDoubleValue(holding.profitLoss);
      final profitRate = _stockDoubleValue(holding.profitLossRate);
      final profitColor = _stockChangeColor(profit ?? profitRate);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _StockTradingSymbolAvatar(
              symbol: holding.symbol,
              name: holding.name,
              logoAsset: '',
              logoUrl: _stockTradingLogoUrlForSymbol(holding.symbol),
              selected: false,
              color: config.color,
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    holding.name.trim().isEmpty ? holding.symbol : holding.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${holding.symbol} · ${_stockFormatNumber(holding.quantity)}주',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.slate,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_stockFormatNumber(holding.marketValue)} ${holding.currency}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_stockSignedNumber(profit)} ${_stockPercentLabel(profitRate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: profitColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget holdingsSurface() {
      return _StockTradingWorkspaceSurface(
        title: '보유 종목',
        icon: Icons.business_center_outlined,
        trailing: '${profile.holdings.length}종목',
        child: Column(
          children: [
            if (profile.holdings.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  loading ? '잔고를 불러오는 중입니다.' : error ?? '보유 종목이 없습니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: KangColors.slate,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              for (
                var index = 0;
                index < math.min(8, profile.holdings.length);
                index++
              ) ...[
                holdingRow(profile.holdings[index]),
                if (index < math.min(8, profile.holdings.length) - 1)
                  const Divider(height: 1, color: _stockPanelBorderColor),
              ],
          ],
        ),
      );
    }

    Widget orderStateRow(TossOpenOrder order) {
      final sideColor = _stockSideColor(order.side);
      final sideLabel = order.side.trim().toUpperCase() == 'BUY' ? '매수' : '매도';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _StockTradingSmallTag(text: sideLabel, color: sideColor),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                order.symbol,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KangColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_stockFormatNumber(order.quantity)}주 · ${_stockFormatNumber(order.price)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KangColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    Widget executionStateRow(TossExecution execution) {
      final sideColor = _stockSideColor(execution.side);
      final sideLabel = execution.side.trim().toUpperCase() == 'BUY'
          ? '매수'
          : '매도';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _StockTradingSmallTag(text: sideLabel, color: sideColor),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    execution.symbol,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    execution.filledAt.trim().isEmpty
                        ? _stockDateTimeLabel(execution.orderedAt)
                        : _stockDateTimeLabel(execution.filledAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.slate,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _stockExecutionDetail(execution),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: KangColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    Widget openOrdersSurface() {
      return _StockTradingWorkspaceSurface(
        title: '미체결 관리',
        icon: Icons.pending_actions_outlined,
        trailing: '${profile.openOrders.length}건',
        child: Column(
          children: [
            if (profile.openOrders.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  loading ? '미체결을 조회 중입니다.' : '미체결 주문 없음',
                  style: const TextStyle(
                    color: KangColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              for (
                var index = 0;
                index < math.min(5, profile.openOrders.length);
                index++
              ) ...[
                orderStateRow(profile.openOrders[index]),
                if (index < math.min(5, profile.openOrders.length) - 1)
                  const Divider(height: 1, color: _stockPanelBorderColor),
              ],
          ],
        ),
      );
    }

    Widget executionsSurface() {
      return _StockTradingWorkspaceSurface(
        title: '최근 체결',
        icon: Icons.playlist_add_check_rounded,
        trailing: '${profile.executions.length}건',
        child: Column(
          children: [
            if (profile.executions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  loading ? '체결 내역을 조회 중입니다.' : '최근 체결 없음',
                  style: const TextStyle(
                    color: KangColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              for (
                var index = 0;
                index < math.min(5, profile.executions.length);
                index++
              ) ...[
                executionStateRow(profile.executions[index]),
                if (index < math.min(5, profile.executions.length) - 1)
                  const Divider(height: 1, color: _stockPanelBorderColor),
              ],
          ],
        ),
      );
    }

    return _StockTradingPanel(
      title: '체결 · 잔고 관리',
      icon: Icons.receipt_long_outlined,
      color: config.color,
      trailing: _StatusPill(text: config.badge, color: config.color),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          if (compact) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  metricsSurface(),
                  const SizedBox(height: 12),
                  holdingsSurface(),
                  const SizedBox(height: 12),
                  openOrdersSurface(),
                  const SizedBox(height: 12),
                  executionsSurface(),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                metricsSurface(),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: holdingsSurface()),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          openOrdersSurface(),
                          const SizedBox(height: 12),
                          executionsSurface(),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StockTradingWorkspaceSurface extends StatelessWidget {
  const _StockTradingWorkspaceSurface({
    required this.title,
    required this.icon,
    required this.trailing,
    required this.child,
    this.expandChild = false,
  });

  final String title;
  final IconData icon;
  final String trailing;
  final Widget child;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
        boxShadow: _stockInnerShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: _stockPanelHeaderColor,
              border: Border(bottom: BorderSide(color: _stockPanelBorderColor)),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: KangColors.slate),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  trailing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class _StockTradingAnalysisLine extends StatelessWidget {
  const _StockTradingAnalysisLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KangColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value.trim().isEmpty ? '--' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingRangeBar extends StatelessWidget {
  const _StockTradingRangeBar({required this.value, required this.color});

  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = ((value ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 16,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Row(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: _stockFallColor.withValues(alpha: 0.14),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(color: color.withValues(alpha: 0.12)),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: _stockRiseColor.withValues(alpha: 0.14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: ratio,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: _stockInnerShadow,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingMiniValue extends StatelessWidget {
  const _StockTradingMiniValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _stockSurfaceMutedColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: KangColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingSmallTag extends StatelessWidget {
  const _StockTradingSmallTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 36),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StockTradingTechnicalProfile {
  const _StockTradingTechnicalProfile({
    required this.candleCount,
    required this.lastPrice,
    required this.ma5,
    required this.ma20,
    required this.ma60,
    required this.lowPrice,
    required this.highPrice,
    required this.rangePosition,
    required this.volumeRatio,
    required this.volatility,
    required this.momentum,
    required this.score,
    required this.trendLabel,
    required this.trendColor,
    required this.signal,
    required this.maAlignment,
    required this.rangePositionLabel,
  });

  final int candleCount;
  final double? lastPrice;
  final double? ma5;
  final double? ma20;
  final double? ma60;
  final double? lowPrice;
  final double? highPrice;
  final double? rangePosition;
  final double? volumeRatio;
  final double? volatility;
  final double? momentum;
  final double score;
  final String trendLabel;
  final Color trendColor;
  final String signal;
  final String maAlignment;
  final String rangePositionLabel;

  factory _StockTradingTechnicalProfile.from(
    List<TossCandle> candles, {
    required TossStockQuote? quote,
    required Color accentColor,
  }) {
    final sorted = _stockSortedCandles(candles);
    final closes = sorted
        .map((item) => _stockDoubleValue(item.closePrice))
        .whereType<double>()
        .toList(growable: false);

    double? averageLast(int count) {
      if (closes.isEmpty) {
        return null;
      }
      final start = math.max(0, closes.length - count);
      final sample = closes.sublist(start);
      return sample.fold<double>(0, (sum, value) => sum + value) /
          sample.length;
    }

    final last = quote?.lastPriceValue ?? (closes.isEmpty ? null : closes.last);
    final ma5 = averageLast(5);
    final ma20 = averageLast(20);
    final ma60 = averageLast(60);
    final recent = sorted.length > 60
        ? sorted.sublist(sorted.length - 60)
        : sorted;
    final lows = recent
        .map((item) => _stockDoubleValue(item.lowPrice))
        .whereType<double>()
        .toList(growable: false);
    final highs = recent
        .map((item) => _stockDoubleValue(item.highPrice))
        .whereType<double>()
        .toList(growable: false);
    final low = lows.isEmpty ? null : lows.reduce(math.min);
    final high = highs.isEmpty ? null : highs.reduce(math.max);
    final range =
        last != null && low != null && high != null && (high - low).abs() > 0
        ? ((last - low) / (high - low) * 100).clamp(0.0, 100.0).toDouble()
        : null;
    final latestVolume = sorted.isEmpty
        ? null
        : _stockDoubleValue(sorted.last.volume);
    final recentVolumes = sorted
        .skip(math.max(0, sorted.length - 20))
        .map((item) => _stockDoubleValue(item.volume))
        .whereType<double>()
        .toList(growable: false);
    final avgVolume = recentVolumes.isEmpty
        ? null
        : recentVolumes.fold<double>(0, (sum, value) => sum + value) /
              recentVolumes.length;
    final volumeRatio =
        latestVolume != null && avgVolume != null && avgVolume > 0
        ? latestVolume / avgVolume
        : null;
    final baseIndex = closes.length > 20 ? closes.length - 21 : 0;
    final baseClose = closes.isEmpty ? null : closes[baseIndex];
    final momentum = last != null && baseClose != null && baseClose != 0
        ? (last - baseClose) / baseClose * 100
        : null;
    final volatility = last != null && low != null && high != null && last != 0
        ? (high - low) / last * 100
        : null;

    String trendLabel;
    Color trendColor;
    if (last != null &&
        ma5 != null &&
        ma20 != null &&
        last >= ma5 &&
        ma5 >= ma20) {
      trendLabel = '상승 추세';
      trendColor = _stockRiseColor;
    } else if (last != null &&
        ma5 != null &&
        ma20 != null &&
        last <= ma5 &&
        ma5 <= ma20) {
      trendLabel = '하락 압력';
      trendColor = _stockFallColor;
    } else {
      trendLabel = '중립 구간';
      trendColor = accentColor;
    }

    var score = 50.0;
    if (momentum != null) {
      score += momentum.clamp(-12.0, 12.0) * 1.6;
    }
    if (last != null && ma20 != null) {
      score += last >= ma20 ? 12 : -12;
    }
    if (ma5 != null && ma20 != null) {
      score += ma5 >= ma20 ? 8 : -8;
    }
    if (volumeRatio != null && volumeRatio >= 1.25 && (momentum ?? 0) > 0) {
      score += 7;
    }
    if (volatility != null && volatility > 24) {
      score -= 6;
    }
    score = score.clamp(0.0, 100.0).toDouble();

    final maAlignment = ma5 == null || ma20 == null
        ? '계산 대기'
        : ma5 >= ma20
        ? '단기 우위'
        : '중기 우위';
    final rangePositionLabel = range == null
        ? '위치 대기'
        : range >= 70
        ? '상단 ${range.toStringAsFixed(0)}%'
        : range <= 30
        ? '하단 ${range.toStringAsFixed(0)}%'
        : '중단 ${range.toStringAsFixed(0)}%';
    final signal = score >= 68
        ? '관심 강화'
        : score <= 38
        ? '방어 우선'
        : '관찰 유지';

    return _StockTradingTechnicalProfile(
      candleCount: sorted.length,
      lastPrice: last,
      ma5: ma5,
      ma20: ma20,
      ma60: ma60,
      lowPrice: low,
      highPrice: high,
      rangePosition: range,
      volumeRatio: volumeRatio,
      volatility: volatility,
      momentum: momentum,
      score: score,
      trendLabel: trendLabel,
      trendColor: trendColor,
      signal: signal,
      maAlignment: maAlignment,
      rangePositionLabel: rangePositionLabel,
    );
  }
}

class _StockTradingOrderReadiness {
  const _StockTradingOrderReadiness({
    required this.currency,
    required this.bestAsk,
    required this.bestBid,
    required this.lastPrice,
    required this.buyingPower,
    required this.askVolume,
    required this.bidVolume,
    required this.tradingAvailable,
    required this.hasOrderbook,
  });

  final String currency;
  final double? bestAsk;
  final double? bestBid;
  final double? lastPrice;
  final double? buyingPower;
  final double askVolume;
  final double bidVolume;
  final bool tradingAvailable;
  final bool hasOrderbook;

  double? get referencePrice => bestAsk ?? lastPrice ?? bestBid;
  double? get spread =>
      bestAsk != null && bestBid != null ? bestAsk! - bestBid! : null;
  double? get spreadPercent =>
      spread != null && referencePrice != null && referencePrice != 0
      ? spread! / referencePrice! * 100
      : null;
  double get imbalance {
    final total = askVolume + bidVolume;
    if (total <= 0) {
      return 0;
    }
    return (bidVolume - askVolume) / total * 100;
  }

  Color get imbalanceColor {
    if (imbalance > 8) {
      return _stockBuyColor;
    }
    if (imbalance < -8) {
      return _stockSellColor;
    }
    return KangColors.slate;
  }

  String get spreadLabel {
    if (spread == null) {
      return '--';
    }
    final percent = spreadPercent == null
        ? ''
        : ' · ${spreadPercent!.toStringAsFixed(2)}%';
    return '${_stockChartValue(spread)}$percent';
  }

  String get affordableQuantityLabel {
    if (buyingPower == null || referencePrice == null || referencePrice == 0) {
      return '--주';
    }
    return '${_stockFormatNumber('${(buyingPower! / referencePrice!).floor()}')}주';
  }

  String get imbalanceLabel => '${imbalance.toStringAsFixed(1)}%';
  bool get canBuyMinimum =>
      buyingPower != null &&
      referencePrice != null &&
      referencePrice! > 0 &&
      buyingPower! >= referencePrice!;
  String get readyLabel => tradingAvailable && hasOrderbook ? '준비됨' : '점검';

  factory _StockTradingOrderReadiness.from({
    required TossStockDashboard? dashboard,
    required TossStockQuote? quote,
    required String currency,
  }) {
    final orderbook = dashboard?.orderbook;
    final asks = orderbook?.asks ?? const <TossOrderbookEntry>[];
    final bids = orderbook?.bids ?? const <TossOrderbookEntry>[];
    final summary = dashboard?.summary;
    return _StockTradingOrderReadiness(
      currency: currency,
      bestAsk: asks.isEmpty ? null : _stockDoubleValue(asks.first.price),
      bestBid: bids.isEmpty ? null : _stockDoubleValue(bids.first.price),
      lastPrice: quote?.lastPriceValue,
      buyingPower: _stockDoubleValue(
        currency == 'KRW' ? summary?.buyingPowerKrw : summary?.buyingPowerUsd,
      ),
      askVolume: asks
          .take(5)
          .fold<double>(
            0,
            (sum, item) => sum + (_stockDoubleValue(item.volume) ?? 0),
          ),
      bidVolume: bids
          .take(5)
          .fold<double>(
            0,
            (sum, item) => sum + (_stockDoubleValue(item.volume) ?? 0),
          ),
      tradingAvailable: summary?.tradingAvailable == true,
      hasOrderbook: asks.isNotEmpty || bids.isNotEmpty,
    );
  }
}

class _StockTradingExecutionProfile {
  const _StockTradingExecutionProfile({
    required this.currency,
    required this.holdings,
    required this.openOrders,
    required this.executions,
    required this.buyingPower,
    required this.accountLabel,
    required this.totalMarketValue,
    required this.totalProfitLoss,
  });

  final String currency;
  final List<TossHolding> holdings;
  final List<TossOpenOrder> openOrders;
  final List<TossExecution> executions;
  final double buyingPower;
  final String accountLabel;
  final double totalMarketValue;
  final double totalProfitLoss;

  String get marketValueLabel =>
      '${_stockChartValue(totalMarketValue)} $currency';
  String get buyingPowerLabel => '${_stockChartValue(buyingPower)} $currency';
  String get estimatedAssetLabel =>
      '${_stockChartValue(totalMarketValue + buyingPower)} $currency';
  String get profitLossLabel =>
      '${_stockSignedNumber(totalProfitLoss)} $currency';

  factory _StockTradingExecutionProfile.from(
    TossStockDashboard? dashboard, {
    required String currency,
  }) {
    final holdings = (dashboard?.holdings ?? const <TossHolding>[])
        .where((item) => _stockMatchesCurrency(item.currency, currency))
        .toList(growable: false);
    final openOrders = (dashboard?.openOrders ?? const <TossOpenOrder>[])
        .where((item) => _stockMatchesCurrency(item.currency, currency))
        .toList(growable: false);
    final executions = (dashboard?.executions ?? const <TossExecution>[])
        .where((item) => _stockMatchesCurrency(item.currency, currency))
        .toList(growable: false);
    final summary = dashboard?.summary;
    return _StockTradingExecutionProfile(
      currency: currency,
      holdings: holdings,
      openOrders: openOrders,
      executions: executions,
      buyingPower:
          _stockDoubleValue(
            currency == 'KRW'
                ? summary?.buyingPowerKrw
                : summary?.buyingPowerUsd,
          ) ??
          0,
      accountLabel: summary?.selectedAccountMasked.trim().isNotEmpty == true
          ? '계좌 ${summary!.selectedAccountMasked}'
          : '실시간 데이터',
      totalMarketValue: holdings.fold<double>(
        0,
        (sum, item) => sum + (_stockDoubleValue(item.marketValue) ?? 0),
      ),
      totalProfitLoss: holdings.fold<double>(
        0,
        (sum, item) => sum + (_stockDoubleValue(item.profitLoss) ?? 0),
      ),
    );
  }
}

Color _stockMaColor(double? price, double? movingAverage, Color fallback) {
  if (price == null || movingAverage == null) {
    return KangColors.slate;
  }
  if (price > movingAverage) {
    return fallback;
  }
  if (price < movingAverage) {
    return _stockFallColor;
  }
  return KangColors.slate;
}

class _StockTradingMarketBoard extends StatelessWidget {
  const _StockTradingMarketBoard({
    required this.api,
    required this.config,
    required this.marketCode,
    required this.symbol,
    required this.dashboard,
    required this.quote,
    required this.loading,
    required this.error,
    required this.selectedInterval,
    required this.onIntervalChanged,
  });

  final TossStockApi api;
  final _StockTradingMarketConfig config;
  final String marketCode;
  final String symbol;
  final TossStockDashboard? dashboard;
  final TossStockQuote? quote;
  final bool loading;
  final String? error;
  final _StockTradingChartInterval selectedInterval;
  final ValueChanged<_StockTradingChartInterval> onIntervalChanged;

  @override
  Widget build(BuildContext context) {
    return _StockTradingPanel(
      title: '시세 · 차트 · 호가',
      icon: Icons.candlestick_chart_rounded,
      color: config.color,
      trailing: Text(
        loading ? '조회 중' : '토스 시세',
        style: const TextStyle(
          color: KangColors.slate,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final chart = _StockTradingChartPlaceholder(
            api: api,
            color: config.color,
            marketCode: marketCode,
            symbol: symbol,
            dashboard: dashboard,
            quote: quote,
            loading: loading,
            selectedInterval: selectedInterval,
            onIntervalChanged: onIntervalChanged,
          );
          final quotePanel = _StockTradingQuotePlaceholder(
            config: config,
            dashboard: dashboard,
            loading: loading,
            error: error,
          );

          if (compact) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SizedBox(height: 300, child: chart),
                  const SizedBox(height: 12),
                  SizedBox(height: 240, child: quotePanel),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(flex: 7, child: chart),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: quotePanel),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StockTradingChartPlaceholder extends StatefulWidget {
  const _StockTradingChartPlaceholder({
    required this.api,
    required this.color,
    required this.marketCode,
    required this.symbol,
    required this.dashboard,
    required this.quote,
    required this.loading,
    required this.selectedInterval,
    required this.onIntervalChanged,
  });

  final TossStockApi api;
  final Color color;
  final String marketCode;
  final String symbol;
  final TossStockDashboard? dashboard;
  final TossStockQuote? quote;
  final bool loading;
  final _StockTradingChartInterval selectedInterval;
  final ValueChanged<_StockTradingChartInterval> onIntervalChanged;

  @override
  State<_StockTradingChartPlaceholder> createState() =>
      _StockTradingChartPlaceholderState();
}

class _StockTradingChartPlaceholderState
    extends State<_StockTradingChartPlaceholder> {
  static const _minVisibleCandles = 24;
  static const _defaultVisibleCandles = 90;
  static const _maxVisibleCandles = 180;
  static const _scrollPixelsPerCandle = 18.0;
  static const _zoomStep = 1.18;

  final _chartViewportKey = GlobalKey();
  List<TossCandle> _olderCandles = const [];
  String? _nextBefore;
  var _loadingOlderCandles = false;
  var _hasOlderCandles = true;
  int? _viewportStart;
  int _visibleCandleTarget = _defaultVisibleCandles;
  int _lastCandleCount = 0;
  int _lastVisibleCount = 0;
  double _dragRemainder = 0;

  @override
  void didUpdateWidget(covariant _StockTradingChartPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marketCode != widget.marketCode ||
        oldWidget.symbol != widget.symbol ||
        oldWidget.selectedInterval.sourceInterval !=
            widget.selectedInterval.sourceInterval) {
      _olderCandles = const [];
      _nextBefore = null;
      _hasOlderCandles = true;
      _viewportStart = null;
      _visibleCandleTarget = _defaultVisibleCandles;
      _dragRemainder = 0;
      return;
    }
    if (oldWidget.selectedInterval != widget.selectedInterval) {
      _viewportStart = null;
      _visibleCandleTarget = _defaultVisibleCandles;
      _dragRemainder = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final rawCandles = _stockMergeCandles(
      _olderCandles,
      widget.dashboard?.candles ?? const <TossCandle>[],
    );
    final allCandles = _stockCandlesForInterval(
      rawCandles,
      widget.selectedInterval,
    );
    final visibleLimit = _visibleCandleTarget
        .clamp(_minVisibleCandles, _maxVisibleCandles)
        .toInt();
    final visibleCount = math.min(visibleLimit, allCandles.length);
    final maxStart = math.max(0, allCandles.length - visibleCount);
    final viewportStart = (_viewportStart ?? maxStart).clamp(0, maxStart);
    final viewportEnd = math.min(
      allCandles.length,
      viewportStart + visibleCount,
    );
    final candles = viewportStart < viewportEnd
        ? allCandles.sublist(viewportStart, viewportEnd)
        : const <TossCandle>[];
    _lastCandleCount = allCandles.length;
    _lastVisibleCount = visibleCount;
    final minZoomVisible = math.min(_minVisibleCandles, allCandles.length);
    final maxZoomVisible = math.min(_maxVisibleCandles, allCandles.length);
    final canZoomIn = visibleCount > minZoomVisible;
    final canZoomOut = visibleCount < maxZoomVisible;

    final latestCandle = candles.isEmpty ? null : candles.last;
    final previousCandle = allCandles.length >= 2 && viewportEnd >= 2
        ? allCandles[math.max(0, viewportEnd - 2)]
        : null;
    final open = _stockDoubleValue(latestCandle?.openPrice);
    final high = _stockDoubleValue(latestCandle?.highPrice);
    final low = _stockDoubleValue(latestCandle?.lowPrice);
    final close = _stockDoubleValue(latestCandle?.closePrice);
    final volume = _stockDoubleValue(latestCandle?.volume);
    final previousClose = _stockDoubleValue(previousCandle?.closePrice);
    final inferredChange = close != null && previousClose != null
        ? close - previousClose
        : null;
    final atLatestViewport = viewportEnd == allCandles.length;
    final changeValue = atLatestViewport
        ? quote?.changeValue ?? inferredChange
        : inferredChange;
    final inferredPercent =
        inferredChange != null && previousClose != null && previousClose != 0
        ? inferredChange / previousClose * 100
        : null;
    final changePercent = atLatestViewport
        ? quote?.changePercentValue ?? inferredPercent
        : inferredPercent;
    final changeColor = _stockChangeColor(changeValue);
    final currency = latestCandle?.currency.isNotEmpty == true
        ? latestCandle!.currency
        : quote?.currency ?? '';
    final priceLabel = atLatestViewport && quote != null && quote.hasPrice
        ? '${_stockFormatNumber(quote.lastPrice)} ${quote.currency}'
        : close == null
        ? '시세 대기'
        : '${_stockChartValue(close)} $currency'.trim();
    final title = quote == null
        ? '${widget.symbol} 차트'
        : '${quote.symbol} ${quote.displayName}';

    return Container(
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final interval in _StockTradingChartInterval.values)
                  _StockTradingChartIntervalPill(
                    interval: interval,
                    selected: interval == widget.selectedInterval,
                    onTap: () => widget.onIntervalChanged(interval),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: _stockPanelBorderColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  priceLabel,
                  style: TextStyle(
                    color: changeColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StockTradingChartMetric(
                    label: 'O',
                    value: _stockChartValue(open),
                    color: KangColors.slate,
                  ),
                  _StockTradingChartMetric(
                    label: 'H',
                    value: _stockChartValue(high),
                    color: _stockRiseColor,
                  ),
                  _StockTradingChartMetric(
                    label: 'L',
                    value: _stockChartValue(low),
                    color: _stockFallColor,
                  ),
                  _StockTradingChartMetric(
                    label: 'C',
                    value: _stockChartValue(close),
                    color: changeColor,
                  ),
                  _StockTradingChartMetric(
                    label: '',
                    value:
                        '${_stockSignedNumber(changeValue)} ${_stockPercentLabel(changePercent)}',
                    color: changeColor,
                  ),
                  _StockTradingChartMetric(
                    label: 'Vol',
                    value: _stockCompactNumber(volume),
                    color: KangColors.slate,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    key: _chartViewportKey,
                    onPointerSignal: _handleChartPointerSignal,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: _handleChartDragUpdate,
                      onHorizontalDragEnd: (_) => _dragRemainder = 0,
                      onDoubleTap: _resetChartViewport,
                      child: CustomPaint(
                        painter: _StockTradingCandleChartPainter(
                          color: widget.color,
                          candles: candles,
                          loading: widget.loading || _loadingOlderCandles,
                        ),
                      ),
                    ),
                  ),
                ),
                if (allCandles.isNotEmpty)
                  Positioned(
                    top: 10,
                    left: 12,
                    child: _StockTradingChartToolbar(
                      color: widget.color,
                      canZoomIn: canZoomIn,
                      canZoomOut: canZoomOut,
                      onZoomIn: () => _zoomViewport(1 / _zoomStep, 0.5),
                      onZoomOut: () => _zoomViewport(_zoomStep, 0.5),
                      onReset: _resetChartViewport,
                    ),
                  ),
                if (_loadingOlderCandles)
                  const Positioned(
                    left: 14,
                    bottom: 12,
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (candles.isEmpty)
                  Center(
                    child: Text(
                      widget.loading ? '시세를 불러오는 중입니다.' : '차트 데이터 대기',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: KangColors.slate,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleChartDragUpdate(DragUpdateDetails details) {
    _dragRemainder += details.primaryDelta ?? details.delta.dx;
    final steps = (_dragRemainder / _scrollPixelsPerCandle).truncate();
    if (steps == 0) {
      return;
    }
    _dragRemainder -= steps * _scrollPixelsPerCandle;
    _shiftViewport(-steps);
  }

  void _handleChartPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      _handleResolvedChartScroll(resolvedEvent as PointerScrollEvent);
    });
  }

  void _handleResolvedChartScroll(PointerScrollEvent event) {
    final delta = event.scrollDelta;
    if (delta.dx.abs() > delta.dy.abs()) {
      _shiftViewportByWheel(delta.dx);
      return;
    }
    if (delta.dy == 0) {
      return;
    }
    final notches = (delta.dy.abs() / 90).clamp(0.25, 5.0).toDouble();
    final scale = math.pow(_zoomStep, notches).toDouble();
    _zoomViewport(
      delta.dy > 0 ? scale : 1 / scale,
      _chartAnchorFraction(event.localPosition),
    );
  }

  void _shiftViewportByWheel(double pixels) {
    if (pixels == 0) {
      return;
    }
    final steps = math.max(1, (pixels.abs() / 40).ceil());
    _shiftViewport(pixels > 0 ? -steps : steps);
  }

  void _zoomViewport(double scale, double anchorFraction) {
    if (_lastCandleCount == 0 || _lastVisibleCount == 0) {
      return;
    }
    final currentVisible = math.min(_lastVisibleCount, _lastCandleCount);
    final minVisible = math.min(_minVisibleCandles, _lastCandleCount);
    final maxVisible = math.min(_maxVisibleCandles, _lastCandleCount);
    final nextVisible = (currentVisible * scale)
        .round()
        .clamp(minVisible, maxVisible)
        .toInt();
    if (nextVisible == currentVisible) {
      return;
    }

    final maxStart = math.max(0, _lastCandleCount - currentVisible);
    final currentStart = (_viewportStart ?? maxStart).clamp(0, maxStart);
    final anchor = anchorFraction.clamp(0.0, 1.0).toDouble();
    final anchoredIndex = currentStart + (currentVisible - 1) * anchor;
    final nextMaxStart = math.max(0, _lastCandleCount - nextVisible);
    final nextStart = (anchoredIndex - (nextVisible - 1) * anchor)
        .round()
        .clamp(0, nextMaxStart)
        .toInt();

    setState(() {
      _visibleCandleTarget = nextVisible;
      _viewportStart = nextStart == nextMaxStart ? null : nextStart;
      _dragRemainder = 0;
    });
    if (nextStart <= 2) {
      _loadOlderCandles();
    }
  }

  void _resetChartViewport() {
    setState(() {
      _visibleCandleTarget = _defaultVisibleCandles;
      _viewportStart = null;
      _dragRemainder = 0;
    });
  }

  double _chartAnchorFraction(Offset localPosition) {
    final size = _chartViewportKey.currentContext?.size;
    if (size == null || size.width <= 78) {
      return 0.5;
    }
    const plotLeft = 10.0;
    final plotWidth = math.max(1.0, size.width - 78.0);
    return ((localPosition.dx - plotLeft) / plotWidth)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _shiftViewport(int delta) {
    if (_lastCandleCount <= _lastVisibleCount || _lastVisibleCount == 0) {
      if (delta < 0) {
        _loadOlderCandles();
      }
      return;
    }

    final maxStart = math.max(0, _lastCandleCount - _lastVisibleCount);
    final current = (_viewportStart ?? maxStart).clamp(0, maxStart);
    final next = (current + delta).clamp(0, maxStart);
    if (next == current) {
      if (delta < 0 && current == 0) {
        _loadOlderCandles();
      }
      return;
    }
    setState(() => _viewportStart = next == maxStart ? null : next);
    if (next <= 2 && delta < 0) {
      _loadOlderCandles();
    }
  }

  Future<void> _loadOlderCandles() async {
    if (_loadingOlderCandles || widget.loading || !_hasOlderCandles) {
      return;
    }
    final baseCandles = widget.dashboard?.candles ?? const <TossCandle>[];
    final mergedCandles = _stockMergeCandles(_olderCandles, baseCandles);
    if (mergedCandles.isEmpty) {
      return;
    }
    final before = (_nextBefore?.trim().isNotEmpty == true)
        ? _nextBefore!.trim()
        : mergedCandles.first.timestamp.trim();
    if (before.isEmpty) {
      return;
    }

    setState(() => _loadingOlderCandles = true);
    try {
      final result = await widget.api.loadCandles(
        market: widget.marketCode,
        symbol: widget.symbol,
        candleInterval: widget.selectedInterval.sourceInterval,
        count: 200,
        before: before,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _olderCandles = _stockMergeCandles(_olderCandles, result.candles);
        final nextBefore = result.nextBefore.trim();
        _nextBefore = nextBefore.isEmpty ? _nextBefore : nextBefore;
        _hasOlderCandles = result.candles.isNotEmpty || nextBefore.isNotEmpty;
        _viewportStart = 0;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
    } finally {
      if (mounted) {
        setState(() => _loadingOlderCandles = false);
      }
    }
  }
}

class _StockTradingQuotePlaceholder extends StatelessWidget {
  const _StockTradingQuotePlaceholder({
    required this.config,
    required this.dashboard,
    required this.loading,
    required this.error,
  });

  final _StockTradingMarketConfig config;
  final TossStockDashboard? dashboard;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final orderbook = dashboard?.orderbook;
    final rows = [
      ...?orderbook?.asks.take(5).map((item) => ('매도', item.price)),
      ...?orderbook?.bids.take(5).map((item) => ('매수', item.price)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: _stockPanelHeaderColor,
              border: Border(bottom: BorderSide(color: _stockPanelBorderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    orderbook == null
                        ? '${dashboard?.summary.primarySymbol ?? ''} 호가'
                        : '${orderbook.symbol} 호가',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: config.color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusPill(text: '실시간', color: config.color),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      loading ? '호가를 불러오는 중입니다.' : error ?? '호가 조회 대기',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: KangColors.slate,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final sideColor = _stockSideColor(row.$1);
                      return Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: sideColor.withValues(alpha: 0.065),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: sideColor.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              row.$1,
                              style: TextStyle(
                                color: sideColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _stockFormatNumber(row.$2),
                              style: TextStyle(
                                color: sideColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemCount: rows.length,
                  ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingChartIntervalPill extends StatelessWidget {
  const _StockTradingChartIntervalPill({
    required this.interval,
    required this.selected,
    required this.onTap,
  });

  final _StockTradingChartInterval interval;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(right: 18),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? const Color(0xFF111827) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                interval.label,
                style: TextStyle(
                  color: selected ? const Color(0xFF111827) : KangColors.slate,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              if (interval.showChevron) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 13,
                  color: selected ? const Color(0xFF111827) : KangColors.slate,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTradingChartMetric extends StatelessWidget {
  const _StockTradingChartMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Text.rich(
        TextSpan(
          children: [
            if (label.isNotEmpty)
              TextSpan(
                text: '$label ',
                style: const TextStyle(color: KangColors.slate),
              ),
            TextSpan(
              text: value,
              style: TextStyle(color: color),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _StockTradingChartToolbar extends StatelessWidget {
  const _StockTradingChartToolbar({
    required this.color,
    required this.canZoomIn,
    required this.canZoomOut,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final Color color;
  final bool canZoomIn;
  final bool canZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.84)),
        boxShadow: [
          BoxShadow(
            color: KangColors.ink.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StockTradingChartToolButton(
              icon: Icons.zoom_in_rounded,
              tooltip: '확대',
              color: color,
              enabled: canZoomIn,
              onTap: onZoomIn,
            ),
            _StockTradingChartToolButton(
              icon: Icons.zoom_out_rounded,
              tooltip: '축소',
              color: color,
              enabled: canZoomOut,
              onTap: onZoomOut,
            ),
            _StockTradingChartToolButton(
              icon: Icons.center_focus_strong_rounded,
              tooltip: '최신 보기',
              color: color,
              enabled: true,
              onTap: onReset,
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTradingChartToolButton extends StatelessWidget {
  const _StockTradingChartToolButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled
        ? color
        : KangColors.slate.withValues(alpha: 0.38);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 32,
          height: 30,
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}

class _StockTradingOrderPanel extends StatefulWidget {
  const _StockTradingOrderPanel({
    required this.api,
    required this.config,
    required this.marketCode,
    required this.symbol,
    required this.dashboard,
    required this.quote,
    required this.loading,
    required this.onOrderSubmitted,
  });

  final TossStockApi api;
  final _StockTradingMarketConfig config;
  final String marketCode;
  final String symbol;
  final TossStockDashboard? dashboard;
  final TossStockQuote? quote;
  final bool loading;
  final VoidCallback onOrderSubmitted;

  @override
  State<_StockTradingOrderPanel> createState() =>
      _StockTradingOrderPanelState();
}

class _StockTradingOrderPanelState extends State<_StockTradingOrderPanel> {
  final TextEditingController _symbolController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  var _selectedSide = 'BUY';
  var _submitting = false;
  String? _orderStatus;
  String _lastAutoPrice = '';

  @override
  void initState() {
    super.initState();
    _syncOrderDefaults(force: true);
  }

  @override
  void didUpdateWidget(covariant _StockTradingOrderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol ||
        oldWidget.dashboard != widget.dashboard ||
        oldWidget.quote != widget.quote ||
        oldWidget.marketCode != widget.marketCode) {
      _syncOrderDefaults();
    }
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _syncOrderDefaults({bool force = false}) {
    final symbol = widget.symbol.trim().toUpperCase();
    if (force ||
        _symbolController.text.trim().isEmpty ||
        _symbolController.text.trim().toUpperCase() != symbol) {
      _symbolController.text = symbol;
    }

    final nextPrice = _stockCleanOrderInput(widget.quote?.lastPrice ?? '');
    if (nextPrice.isEmpty) {
      return;
    }

    final currentPrice = _stockCleanOrderInput(_priceController.text);
    if (force || currentPrice.isEmpty || currentPrice == _lastAutoPrice) {
      final formattedPrice = _stockFormatEditableNumber(
        nextPrice,
        allowDecimal: true,
      );
      _priceController.value = TextEditingValue(
        text: formattedPrice,
        selection: TextSelection.collapsed(offset: formattedPrice.length),
      );
      _lastAutoPrice = nextPrice;
    }
  }

  bool get _canSubmit {
    final tradingAvailable = widget.dashboard?.summary.tradingAvailable == true;
    return !_submitting &&
        !widget.loading &&
        tradingAvailable &&
        _symbolController.text.trim().isNotEmpty &&
        _stockCleanOrderInput(_priceController.text).isNotEmpty &&
        _stockCleanOrderInput(_quantityController.text).isNotEmpty;
  }

  Future<void> _confirmAndSubmitOrder() async {
    final symbol = _symbolController.text.trim().toUpperCase();
    final price = _stockCleanOrderInput(_priceController.text);
    final quantity = _stockCleanOrderInput(_quantityController.text);
    final validationError = _validateLimitOrder(
      symbol: symbol,
      price: price,
      quantity: quantity,
    );
    if (validationError != null) {
      _showOrderSnack(validationError, _stockFallColor);
      return;
    }

    final sideLabel = _selectedSide == 'BUY' ? '매수' : '매도';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final sideColor = _stockSideColor(_selectedSide);
        return AlertDialog(
          title: Text('실제 $sideLabel 주문 확인'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('토스증권 계좌로 실제 주문을 전송합니다.'),
              const SizedBox(height: 12),
              _StockTradingOrderConfirmRow(label: '종목', value: symbol),
              _StockTradingOrderConfirmRow(label: '구분', value: sideLabel),
              const _StockTradingOrderConfirmRow(label: '주문 유형', value: '지정가'),
              _StockTradingOrderConfirmRow(
                label: '주문 가격',
                value: '${_stockFormatNumber(price)} ${widget.config.badge}',
              ),
              _StockTradingOrderConfirmRow(
                label: '수량',
                value: '${_stockFormatNumber(quantity)}주',
              ),
              const SizedBox(height: 10),
              Text(
                '확인을 누르면 실제 주문이 접수됩니다.',
                style: TextStyle(color: sideColor, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: sideColor),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('$sideLabel 주문 전송'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _submitting = true;
      _orderStatus = '주문 전송 중입니다.';
    });

    try {
      final result = await widget.api.submitOrder(
        TossOrderSubmitRequest(
          symbol: symbol,
          side: _selectedSide,
          orderType: 'LIMIT',
          quantity: quantity,
          price: price,
          orderAmount: '',
        ),
      );
      if (!mounted) {
        return;
      }
      final orderId = result.orderId.trim();
      final message = orderId.isEmpty
          ? '주문이 접수되었습니다.'
          : '주문이 접수되었습니다. 주문번호 $orderId';
      setState(() => _orderStatus = message);
      _showOrderSnack(message, _stockSideColor(_selectedSide));
      widget.onOrderSubmitted();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString();
      setState(() => _orderStatus = message);
      _showOrderSnack(message, _stockFallColor);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showOrderSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedSideColor = _stockSideColor(_selectedSide);
    final sideLabel = _selectedSide == 'BUY' ? '매수' : '매도';
    final quote = widget.quote;
    final summary = widget.dashboard?.summary;
    final tradingAvailable = summary?.tradingAvailable == true;
    final tradingNotice = _stockTradingOrderNotice(
      summary: summary,
      loading: widget.loading,
    );
    final buyingPower = widget.config.badge == 'KRW'
        ? summary?.buyingPowerKrw
        : summary?.buyingPowerUsd;
    return _StockTradingPanel(
      title: '주문 패널',
      icon: Icons.price_change_outlined,
      color: widget.config.color,
      trailing: _StatusPill(
        text: widget.config.badge,
        color: widget.config.color,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return selectedSideColor.withValues(alpha: 0.12);
                  }
                  return Colors.white;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return selectedSideColor;
                  }
                  return KangColors.slate;
                }),
                iconColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return selectedSideColor;
                  }
                  return KangColors.slate;
                }),
                side: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return BorderSide(color: selectedSideColor, width: 1.2);
                  }
                  return BorderSide(
                    color: KangColors.line.withValues(alpha: 0.9),
                  );
                }),
              ),
              segments: const [
                ButtonSegment(
                  value: 'BUY',
                  icon: Icon(Icons.trending_up_rounded),
                  label: Text('매수'),
                ),
                ButtonSegment(
                  value: 'SELL',
                  icon: Icon(Icons.trending_down_rounded),
                  label: Text('매도'),
                ),
              ],
              selected: {_selectedSide},
              onSelectionChanged: (selection) {
                final next = selection.isEmpty ? null : selection.first;
                if (next != null) {
                  setState(() => _selectedSide = next);
                }
              },
            ),
            const SizedBox(height: 14),
            _StockTradingOrderTextField(
              controller: _symbolController,
              label: '종목',
              hintText: '예: 005930',
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _StockTradingOrderTextField(
              controller: _priceController,
              label: '주문 가격',
              hintText: widget.config.badge,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [
                _StockTradingNumberTextInputFormatter(allowDecimal: true),
              ],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _StockTradingOrderTextField(
              controller: _quantityController,
              label: '수량',
              hintText: '1',
              keyboardType: TextInputType.number,
              inputFormatters: const [_StockTradingNumberTextInputFormatter()],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: selectedSideColor,
                disabledBackgroundColor: KangColors.line,
                disabledForegroundColor: KangColors.slate,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text(_submitting ? '주문 전송 중' : '$sideLabel 주문 확인'),
              onPressed: _canSubmit ? _confirmAndSubmitOrder : null,
            ),
            const SizedBox(height: 12),
            _CalendarMessage(
              icon: Icons.security_rounded,
              text: tradingAvailable
                  ? '최종 확인창에서 확인해야 실제 주문이 전송됩니다.'
                  : tradingNotice,
              color: tradingAvailable ? selectedSideColor : KangColors.slate,
            ),
            if ((quote?.lastPrice.trim().isNotEmpty ?? false) ||
                (buyingPower?.trim().isNotEmpty ?? false) ||
                tradingNotice.trim().isNotEmpty ||
                (_orderStatus?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 10),
              _StockTradingOrderInfoBox(
                color: selectedSideColor,
                lines: [
                  if (quote?.lastPrice.trim().isNotEmpty ?? false)
                    '현재가 ${_stockFormatNumber(quote!.lastPrice)} ${quote.currency}',
                  if (buyingPower?.trim().isNotEmpty ?? false)
                    '매수 가능 ${_stockFormatNumber(buyingPower!)} ${widget.config.badge}',
                  if (tradingNotice.trim().isNotEmpty) tradingNotice,
                  if (_orderStatus?.trim().isNotEmpty ?? false)
                    _orderStatus!.trim(),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StockTradingOrderTextField extends StatelessWidget {
  const _StockTradingOrderTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.onChanged,
    this.keyboardType,
    this.inputFormatters = const [],
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: _stockSurfaceMutedColor,
        labelText: label,
        hintText: hintText,
        labelStyle: const TextStyle(
          color: KangColors.slate,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(
          color: KangColors.ink,
          fontWeight: FontWeight.w800,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _stockPanelBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _stockRiseColor, width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _stockPanelBorderColor),
        ),
      ),
    );
  }
}

class _StockTradingOrderInfoBox extends StatelessWidget {
  const _StockTradingOrderInfoBox({required this.color, required this.lines});

  final Color color;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.065),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KangColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StockTradingOrderConfirmRow extends StatelessWidget {
  const _StockTradingOrderConfirmRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                color: KangColors.slate,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: KangColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingNumberTextInputFormatter extends TextInputFormatter {
  const _StockTradingNumberTextInputFormatter({this.allowDecimal = false});

  final bool allowDecimal;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawText = newValue.text;
    final selectionEnd = newValue.selection.end.clamp(0, rawText.length);
    final rawBeforeCursor = rawText.substring(0, selectionEnd);
    final cleanBeforeCursor = _stockSanitizeNumberInput(
      rawBeforeCursor,
      allowDecimal: allowDecimal,
    );
    final cleanText = _stockSanitizeNumberInput(
      rawText,
      allowDecimal: allowDecimal,
    );

    final formatted = _stockFormatEditableNumber(
      cleanText,
      allowDecimal: allowDecimal,
    );
    final formattedBeforeCursor = _stockFormatEditableNumber(
      cleanBeforeCursor,
      allowDecimal: allowDecimal,
    );
    final cursorOffset = math.min(
      formattedBeforeCursor.length,
      formatted.length,
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }
}

class _StockTradingExecutionPanel extends StatelessWidget {
  const _StockTradingExecutionPanel({
    required this.config,
    required this.dashboard,
    required this.loading,
    required this.error,
  });

  final _StockTradingMarketConfig config;
  final TossStockDashboard? dashboard;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final summary = dashboard?.summary;
    final currency = config.badge;
    final holdings = (dashboard?.holdings ?? const <TossHolding>[])
        .where((item) => _stockMatchesCurrency(item.currency, currency))
        .toList(growable: false);
    final openOrders = (dashboard?.openOrders ?? const <TossOpenOrder>[])
        .where((item) => _stockMatchesCurrency(item.currency, currency))
        .toList(growable: false);
    final executions = (dashboard?.executions ?? const <TossExecution>[])
        .where((item) => _stockMatchesCurrency(item.currency, currency))
        .toList(growable: false);
    final buyingPower = currency == 'KRW'
        ? summary?.buyingPowerKrw
        : summary?.buyingPowerUsd;
    final balanceLabel = buyingPower?.trim().isNotEmpty == true
        ? '${_stockFormatNumber(buyingPower!)} $currency'
        : loading
        ? '조회 중'
        : '0 $currency';
    final accountLabel =
        summary?.selectedAccountMasked.trim().isNotEmpty == true
        ? '계좌 ${summary!.selectedAccountMasked}'
        : loading
        ? '조회 중'
        : '실시간 데이터';
    final balanceCaption = holdings.isEmpty
        ? accountLabel
        : '${holdings.length}종목 · $accountLabel';
    final statusText = loading
        ? '조회 중'
        : error?.trim().isNotEmpty == true
        ? '오류'
        : accountLabel;

    return _StockTradingPanel(
      title: '체결 · 미체결 · 잔고',
      icon: Icons.receipt_long_outlined,
      color: config.color,
      trailing: Text(
        statusText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: KangColors.slate,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Expanded(
                    child: _StockTradingSummaryBox(
                      title: '체결 현황',
                      value: '${executions.length}건',
                      caption: executions.isEmpty ? '체결 없음' : '최근 체결',
                      color: config.color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StockTradingSummaryBox(
                      title: '미체결',
                      value: '${openOrders.length}건',
                      caption: openOrders.isEmpty ? '주문 없음' : '대기 주문',
                      color: config.color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StockTradingSummaryBox(
                      title: config.balanceTitle,
                      value: balanceLabel,
                      caption: balanceCaption,
                      color: config.color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Expanded(
                    child: _StockTradingExecutionList(
                      title: '최근 체결',
                      emptyText: loading ? '조회 중' : '체결 내역 없음',
                      color: config.color,
                      children: [
                        for (final execution in executions.take(2))
                          _StockTradingExecutionLine(
                            leading:
                                execution.side.trim().toUpperCase() == 'BUY'
                                ? '매수'
                                : '매도',
                            title: execution.symbol,
                            detail: _stockExecutionDetail(execution),
                            color: _stockSideColor(execution.side),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StockTradingExecutionList(
                      title: '미체결 주문',
                      emptyText: loading ? '조회 중' : '미체결 주문 없음',
                      color: config.color,
                      children: [
                        for (final order in openOrders.take(2))
                          _StockTradingExecutionLine(
                            leading: order.side.trim().toUpperCase() == 'BUY'
                                ? '매수'
                                : '매도',
                            title: order.symbol,
                            detail:
                                '${_stockFormatNumber(order.quantity)}주 · ${_stockFormatNumber(order.price)} ${order.currency}',
                            color: _stockSideColor(order.side),
                          ),
                      ],
                    ),
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

class _StockTradingSummaryBox extends StatelessWidget {
  const _StockTradingSummaryBox({
    required this.title,
    required this.value,
    required this.color,
    this.caption = '',
  });

  final String title;
  final String value;
  final Color color;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.13)),
        boxShadow: _stockInnerShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: value.length > 10 ? 16 : 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (caption.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KangColors.slate,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StockTradingExecutionList extends StatelessWidget {
  const _StockTradingExecutionList({
    required this.title,
    required this.emptyText,
    required this.color,
    required this.children,
  });

  final String title;
  final String emptyText;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _stockSurfaceMutedColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          if (children.isEmpty)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  emptyText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: children,
              ),
            ),
        ],
      ),
    );
  }
}

class _StockTradingExecutionLine extends StatelessWidget {
  const _StockTradingExecutionLine({
    required this.leading,
    required this.title,
    required this.detail,
    required this.color,
  });

  final String leading;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              leading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const Color _stockCanvasColor = Color(0xFFF3F5F9);
const Color _stockSurfaceColor = Color(0xFFFFFFFF);
const Color _stockSurfaceMutedColor = Color(0xFFF7F9FC);
const Color _stockPanelHeaderColor = Color(0xFFFBFCFE);
const Color _stockPanelBorderColor = Color(0xFFE1E7F0);
const Color _stockRailColor = Color(0xFF111827);
const Color _stockRiseColor = Color(0xFFE53935);
const Color _stockFallColor = Color(0xFF2563EB);
const Color _stockBuyColor = _stockRiseColor;
const Color _stockSellColor = _stockFallColor;
const List<BoxShadow> _stockPanelShadow = [
  BoxShadow(color: Color(0x0D0B1220), blurRadius: 24, offset: Offset(0, 12)),
];
const List<BoxShadow> _stockInnerShadow = [
  BoxShadow(color: Color(0x080B1220), blurRadius: 14, offset: Offset(0, 7)),
];

Color _stockChangeColor(double? value) {
  if (value == null || value == 0) {
    return KangColors.slate;
  }
  return value > 0 ? _stockRiseColor : _stockFallColor;
}

Color _stockSideColor(String side) {
  final normalized = side.trim().toLowerCase();
  if (normalized == 'buy' || normalized == '매수') {
    return _stockBuyColor;
  }
  if (normalized == 'sell' || normalized == '매도') {
    return _stockSellColor;
  }
  return KangColors.slate;
}

Color _stockAvatarColor(String symbol) {
  const colors = [
    Color(0xFF1D4ED8),
    Color(0xFF059669),
    Color(0xFFDB2777),
    Color(0xFFF59E0B),
    Color(0xFF7C3AED),
    Color(0xFF0F766E),
  ];
  final seed = symbol.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  return colors[seed % colors.length];
}

double? _stockDoubleValue(String? value) {
  final normalized = value?.replaceAll(',', '').trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }
  return double.tryParse(normalized);
}

_StockTradingDailyChange? _stockDailyChangeFromCandles(
  List<TossCandle> candles, {
  required String lastPrice,
}) {
  final sorted = _stockSortedCandles(candles);
  if (sorted.length < 2) {
    return null;
  }

  final currentPrice =
      _stockDoubleValue(lastPrice) ?? _stockDoubleValue(sorted.last.closePrice);
  final previousClose = _stockDoubleValue(sorted[sorted.length - 2].closePrice);
  if (currentPrice == null || previousClose == null || previousClose == 0) {
    return null;
  }

  final change = currentPrice - previousClose;
  return _StockTradingDailyChange(
    lastPrice: lastPrice,
    change: change,
    percent: change / previousClose * 100,
  );
}

String _stockChartValue(double? value) {
  if (value == null) {
    return '--';
  }
  return _stockFormatNumber(value.toStringAsFixed(value >= 1000 ? 0 : 2));
}

String _stockIntervalDisplayLabel(_StockTradingChartInterval interval) {
  switch (interval.label) {
    case '5m':
      return '5분';
    case '10m':
      return '10분';
    case '30m':
      return '30분';
    case '1h':
      return '1시간';
    case '4h':
      return '4시간';
    case 'D':
      return '일봉';
    case 'W':
      return '주봉';
    case 'M':
      return '월봉';
    case 'Y':
      return '연봉';
  }
  return interval.label;
}

String _stockDateTimeLabel(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return '-';
  }
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) {
    return normalized;
  }
  final local = parsed.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String _stockSignedNumber(double? value) {
  if (value == null) {
    return '--';
  }
  final sign = value > 0 ? '+' : '';
  return '$sign${_stockFormatNumber(value.toStringAsFixed(value.abs() >= 1000 ? 0 : 2))}';
}

String _stockPercentLabel(double? value) {
  if (value == null) {
    return '';
  }
  final sign = value > 0 ? '+' : '';
  return '($sign${value.toStringAsFixed(2)}%)';
}

String _stockCompactNumber(double? value) {
  if (value == null) {
    return '--';
  }
  if (value >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(2)}B';
  }
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(2)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return _stockFormatNumber(value.toStringAsFixed(0));
}

String _stockFormatNumber(String value) {
  final normalized = value.replaceAll(',', '').trim();
  if (normalized.isEmpty) {
    return '--';
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null) {
    return value;
  }
  final negative = normalized.startsWith('-');
  final unsigned = negative ? normalized.substring(1) : normalized;
  final parts = unsigned.split('.');
  final integer = parts.first;
  final decimal = parts.length > 1 ? parts.sublist(1).join('.') : '';
  final buffer = StringBuffer();
  for (var index = 0; index < integer.length; index++) {
    final remaining = integer.length - index;
    buffer.write(integer[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  final formatted = '${negative ? '-' : ''}$buffer';
  final trimmedDecimal = decimal.replaceFirst(RegExp(r'0+$'), '');
  return trimmedDecimal.isEmpty ? formatted : '$formatted.$trimmedDecimal';
}

String _stockFormatEditableNumber(String value, {required bool allowDecimal}) {
  final clean = _stockSanitizeNumberInput(value, allowDecimal: allowDecimal);
  if (clean.isEmpty) {
    return '';
  }

  final hasTrailingDecimal = allowDecimal && clean.endsWith('.');
  final parts = clean.split('.');
  final integerPart = parts.first.isEmpty ? '0' : parts.first;
  final decimalPart = allowDecimal && parts.length > 1
      ? parts.sublist(1).join('')
      : '';
  final formattedInteger = _stockFormatNumber(integerPart);
  if (!allowDecimal || (!hasTrailingDecimal && decimalPart.isEmpty)) {
    return formattedInteger;
  }
  return '$formattedInteger.$decimalPart';
}

String _stockSanitizeNumberInput(String value, {required bool allowDecimal}) {
  final buffer = StringBuffer();
  var hasDecimal = false;
  for (final codeUnit in value.codeUnits) {
    final isDigit = codeUnit >= 48 && codeUnit <= 57;
    if (isDigit) {
      buffer.writeCharCode(codeUnit);
      continue;
    }
    if (allowDecimal && codeUnit == 46 && !hasDecimal) {
      buffer.write('.');
      hasDecimal = true;
    }
  }
  return buffer.toString();
}

String _stockCleanOrderInput(String value) {
  return value.replaceAll(',', '').trim();
}

bool _stockMatchesCurrency(String value, String currency) {
  final normalizedValue = value.trim().toUpperCase();
  final normalizedCurrency = currency.trim().toUpperCase();
  return normalizedValue.isEmpty || normalizedValue == normalizedCurrency;
}

String _stockTradingOrderNotice({
  required TossStockSummary? summary,
  required bool loading,
}) {
  if (summary?.tradingAvailable == true) {
    return '';
  }
  final blockedReason = summary?.tradingBlockedReason.trim() ?? '';
  if (blockedReason.isNotEmpty) {
    return blockedReason;
  }
  if (loading) {
    return '실전 주문 상태를 확인 중입니다.';
  }
  return '실전 주문 가능 여부를 확인하지 못했습니다.';
}

String _stockExecutionDetail(TossExecution execution) {
  final quantity = _stockFormatNumber(execution.filledQuantity);
  final averagePrice = execution.averageFilledPrice.trim();
  final filledAmount = execution.filledAmount.trim();
  final priceLabel = averagePrice.isNotEmpty
      ? _stockFormatNumber(averagePrice)
      : filledAmount.isNotEmpty
      ? _stockFormatNumber(filledAmount)
      : '-';
  return '$quantity주 · $priceLabel ${execution.currency}';
}

String? _validateLimitOrder({
  required String symbol,
  required String price,
  required String quantity,
}) {
  if (!RegExp(r'^[A-Za-z0-9.\-]{1,20}$').hasMatch(symbol)) {
    return '종목 코드를 확인해 주세요.';
  }
  final parsedPrice = double.tryParse(price);
  if (parsedPrice == null || parsedPrice <= 0) {
    return '주문 가격은 0보다 커야 합니다.';
  }
  if (!RegExp(r'^\d+$').hasMatch(quantity)) {
    return '수량은 1 이상의 정수만 입력할 수 있습니다.';
  }
  final parsedQuantity = int.tryParse(quantity);
  if (parsedQuantity == null || parsedQuantity <= 0) {
    return '수량은 1 이상이어야 합니다.';
  }
  return null;
}

List<TossCandle> _stockMergeCandles(
  List<TossCandle> olderCandles,
  List<TossCandle> newerCandles,
) {
  final byKey = <String, TossCandle>{};
  var fallbackIndex = 0;
  void addCandle(TossCandle candle) {
    final timestamp = candle.timestamp.trim();
    final key = timestamp.isNotEmpty
        ? timestamp
        : 'fallback-${fallbackIndex++}-${candle.openPrice}-${candle.closePrice}';
    byKey[key] = candle;
  }

  for (final candle in olderCandles) {
    addCandle(candle);
  }
  for (final candle in newerCandles) {
    addCandle(candle);
  }
  return _stockSortedCandles(byKey.values.toList(growable: false));
}

List<TossCandle> _stockCandlesForInterval(
  List<TossCandle> candles,
  _StockTradingChartInterval interval,
) {
  final sorted = _stockSortedCandles(candles);
  if (interval.bucketMinutes <= 1 || sorted.length < 2) {
    return sorted;
  }

  final bucketSizeMs = interval.bucketMinutes * 60000;
  final result = <TossCandle>[];
  _StockTradingCandleBucket? bucket;
  for (var index = 0; index < sorted.length; index++) {
    final candle = sorted[index];
    final timestamp = DateTime.tryParse(candle.timestamp);
    final bucketKey = timestamp == null
        ? index ~/ interval.bucketMinutes
        : timestamp.millisecondsSinceEpoch ~/ bucketSizeMs;
    if (bucket == null || bucket.key != bucketKey) {
      final completed = bucket?.toCandle();
      if (completed != null) {
        result.add(completed);
      }
      bucket = _StockTradingCandleBucket(bucketKey);
    }
    bucket.add(candle);
  }
  final completed = bucket?.toCandle();
  if (completed != null) {
    result.add(completed);
  }
  return result.isEmpty ? sorted : result;
}

List<TossCandle> _stockSortedCandles(List<TossCandle> candles) {
  final indexed = [
    for (var index = 0; index < candles.length; index++)
      _StockTradingIndexedCandle(index, candles[index]),
  ];
  indexed.sort((a, b) {
    final aTime = DateTime.tryParse(a.candle.timestamp);
    final bTime = DateTime.tryParse(b.candle.timestamp);
    if (aTime != null && bTime != null) {
      final comparison = aTime.compareTo(bTime);
      if (comparison != 0) {
        return comparison;
      }
    }
    return a.index.compareTo(b.index);
  });
  return indexed.map((item) => item.candle).toList(growable: false);
}

String _stockCandleNumber(double value) {
  if (!value.isFinite) {
    return '';
  }
  final fixed = value.abs() >= 1000
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(4);
  if (!fixed.contains('.')) {
    return fixed;
  }
  final trimmed = fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}

class _StockTradingIndexedCandle {
  const _StockTradingIndexedCandle(this.index, this.candle);

  final int index;
  final TossCandle candle;
}

class _StockTradingCandleBucket {
  _StockTradingCandleBucket(this.key);

  final int key;
  double? _open;
  double? _high;
  double? _low;
  double? _close;
  double _volume = 0;
  String _timestamp = '';
  String _currency = '';

  void add(TossCandle candle) {
    final close = _stockDoubleValue(candle.closePrice);
    final open = _stockDoubleValue(candle.openPrice) ?? close;
    final high = _stockDoubleValue(candle.highPrice) ?? close ?? open;
    final low = _stockDoubleValue(candle.lowPrice) ?? close ?? open;
    if (open == null || high == null || low == null || close == null) {
      return;
    }
    _open ??= open;
    _high = _high == null ? high : math.max(_high!, high);
    _low = _low == null ? low : math.min(_low!, low);
    _close = close;
    _volume += _stockDoubleValue(candle.volume) ?? 0;
    _timestamp = candle.timestamp;
    if (_currency.isEmpty) {
      _currency = candle.currency;
    }
  }

  TossCandle? toCandle() {
    final open = _open;
    final high = _high;
    final low = _low;
    final close = _close;
    if (open == null || high == null || low == null || close == null) {
      return null;
    }
    return TossCandle(
      timestamp: _timestamp,
      openPrice: _stockCandleNumber(open),
      highPrice: _stockCandleNumber(high),
      lowPrice: _stockCandleNumber(low),
      closePrice: _stockCandleNumber(close),
      volume: _stockCandleNumber(_volume),
      currency: _currency,
    );
  }
}

class _StockTradingCandlePoint {
  const _StockTradingCandlePoint({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.timestamp,
  });

  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final String timestamp;

  bool get up => close >= open;
}

class _StockTradingCandleChartPainter extends CustomPainter {
  const _StockTradingCandleChartPainter({
    required this.color,
    required this.candles,
    required this.loading,
  });

  final Color color;
  final List<TossCandle> candles;
  final bool loading;

  @override
  void paint(Canvas canvas, Size size) {
    final chartRect = Rect.fromLTWH(
      10,
      8,
      math.max(1, size.width - 78),
      math.max(1, size.height - 70),
    );
    final volumeRect = Rect.fromLTWH(
      chartRect.left,
      chartRect.bottom + 10,
      chartRect.width,
      34,
    );
    final gridPaint = Paint()
      ..color = const Color(0xFFEFF3F8)
      ..strokeWidth = 1;
    for (var i = 0; i <= 5; i++) {
      final y = chartRect.top + chartRect.height * i / 5;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }
    for (var i = 0; i <= 8; i++) {
      final x = chartRect.left + chartRect.width * i / 8;
      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, volumeRect.bottom),
        gridPaint,
      );
    }

    final parsed = candles
        .map(_parseCandle)
        .whereType<_StockTradingCandlePoint>()
        .toList(growable: false);
    if (parsed.isEmpty) {
      _drawMutedWave(canvas, chartRect, color);
      return;
    }

    final minPrice = parsed.map((item) => item.low).reduce(math.min);
    final maxPrice = parsed.map((item) => item.high).reduce(math.max);
    final pricePadding = math.max(
      (maxPrice - minPrice) * 0.08,
      maxPrice * 0.002,
    );
    final lowBound = minPrice - pricePadding;
    final highBound = maxPrice + pricePadding;
    final range = math.max(highBound - lowBound, 1);
    final maxVolume = math.max(
      parsed.map((item) => item.volume).fold<double>(0, math.max),
      1,
    );

    double yFor(double price) =>
        chartRect.bottom - ((price - lowBound) / range) * chartRect.height;

    for (var i = 0; i <= 5; i++) {
      final value = highBound - range * i / 5;
      _drawChartText(
        canvas,
        _stockChartValue(value),
        Offset(
          chartRect.right + 8,
          chartRect.top + chartRect.height * i / 5 - 7,
        ),
        const Color(0xFF8A94A6),
        11,
        FontWeight.w700,
      );
    }

    final step = chartRect.width / parsed.length;
    final candleWidth = math.max(2.2, math.min(16.0, step * 0.66));
    final candleRadius = Radius.circular(
      math.max(1.5, math.min(3.0, candleWidth * 0.18)),
    );
    for (var i = 0; i < parsed.length; i++) {
      final candle = parsed[i];
      final centerX = chartRect.left + step * (i + 0.5);
      final candleColor = candle.up ? _stockRiseColor : _stockFallColor;
      final highY = yFor(candle.high);
      final lowY = yFor(candle.low);
      var openY = yFor(candle.open);
      var closeY = yFor(candle.close);
      if ((openY - closeY).abs() < 2) {
        final centerY = (openY + closeY) / 2;
        openY = centerY - 1;
        closeY = centerY + 1;
      }
      canvas.drawLine(
        Offset(centerX, highY),
        Offset(centerX, lowY),
        Paint()
          ..color = candleColor
          ..strokeWidth = math.max(1, candleWidth * 0.24)
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            centerX - candleWidth / 2,
            math.min(openY, closeY),
            centerX + candleWidth / 2,
            math.max(openY, closeY),
          ),
          candleRadius,
        ),
        Paint()..color = candleColor,
      );
      final rawVolumeHeight = (candle.volume / maxVolume) * volumeRect.height;
      final volumeHeight = rawVolumeHeight <= 0
          ? 0.0
          : math.max(1.0, rawVolumeHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            centerX - candleWidth / 2,
            volumeRect.bottom - volumeHeight,
            candleWidth,
            volumeHeight,
          ),
          candleRadius,
        ),
        Paint()..color = candleColor.withValues(alpha: 0.22),
      );
    }

    final current = parsed.last.close;
    final currentY = yFor(current);
    final currentColor = parsed.last.up ? _stockRiseColor : _stockFallColor;
    _drawDashedLine(
      canvas,
      Offset(chartRect.left, currentY),
      Offset(chartRect.right, currentY),
      Paint()
        ..color = currentColor.withValues(alpha: 0.42)
        ..strokeWidth = 1,
    );
    _drawPriceMarker(
      canvas,
      Offset(chartRect.right + 2, currentY),
      current,
      currentColor,
    );
  }

  _StockTradingCandlePoint? _parseCandle(TossCandle candle) {
    final close = _stockDoubleValue(candle.closePrice);
    final open = _stockDoubleValue(candle.openPrice) ?? close;
    final high = _stockDoubleValue(candle.highPrice) ?? close ?? open;
    final low = _stockDoubleValue(candle.lowPrice) ?? close ?? open;
    if (open == null || high == null || low == null || close == null) {
      return null;
    }
    return _StockTradingCandlePoint(
      open: open,
      high: high,
      low: low,
      close: close,
      volume: _stockDoubleValue(candle.volume) ?? 0,
      timestamp: candle.timestamp,
    );
  }

  void _drawMutedWave(Canvas canvas, Rect rect, Color accent) {
    final path = Path()
      ..moveTo(rect.left, rect.center.dy)
      ..cubicTo(
        rect.left + rect.width * 0.2,
        rect.top + rect.height * 0.68,
        rect.left + rect.width * 0.34,
        rect.top + rect.height * 0.28,
        rect.left + rect.width * 0.52,
        rect.center.dy,
      )
      ..cubicTo(
        rect.left + rect.width * 0.7,
        rect.bottom - rect.height * 0.2,
        rect.left + rect.width * 0.82,
        rect.top + rect.height * 0.24,
        rect.right,
        rect.top + rect.height * 0.36,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: loading ? 0.28 : 0.16)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    var x = start.dx;
    while (x < end.dx) {
      canvas.drawLine(
        Offset(x, start.dy),
        Offset(math.min(x + dash, end.dx), end.dy),
        paint,
      );
      x += dash + gap;
    }
  }

  void _drawPriceMarker(
    Canvas canvas,
    Offset anchor,
    double price,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: _stockChartValue(price),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromLTWH(
      anchor.dx,
      anchor.dy - 11,
      painter.width + 12,
      22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = color,
    );
    painter.paint(canvas, Offset(rect.left + 6, rect.top + 4));
  }

  void _drawChartText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
    FontWeight fontWeight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _StockTradingCandleChartPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.loading != loading ||
        oldDelegate.candles != candles;
  }
}

class _StockTradingPlaceholderPanel extends StatefulWidget {
  const _StockTradingPlaceholderPanel({required this.module});

  final _HomeModule module;

  @override
  State<_StockTradingPlaceholderPanel> createState() =>
      _StockTradingPlaceholderPanelState();
}

class _StockTradingPlaceholderPanelState
    extends State<_StockTradingPlaceholderPanel> {
  var _selectedMarket = _StockTradingMarket.domestic;

  _StockTradingMarketConfig get _marketConfig =>
      _StockTradingMarketConfig.byMarket(_selectedMarket);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _marketConfig;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
        boxShadow: [
          BoxShadow(
            color: widget.module.accent.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.module.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(widget.module.icon, color: widget.module.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '주식 거래 대시보드',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '토스증권 Open API 기반 실시간 시세와 실제 주문 상태를 확인합니다.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: KangColors.slate,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(text: '실전', color: widget.module.accent),
              ],
            ),
            const SizedBox(height: 16),
            _StockTradingMarketTabs(
              selected: _selectedMarket,
              onChanged: (market) => setState(() => _selectedMarket = market),
            ),
            const SizedBox(height: 14),
            _StockTradingMarketHeader(config: config),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final cards = config.items
                    .map(
                      (item) => _StockTradingReadyItem(
                        icon: item.icon,
                        title: item.title,
                        value: item.value,
                        color: config.color,
                      ),
                    )
                    .toList(growable: false);

                final content = [
                  _StockTradingReadyItem(
                    icon: Icons.account_balance_wallet_outlined,
                    title: config.balanceTitle,
                    value: config.balanceValue,
                    color: config.color,
                  ),
                ];

                if (compact) {
                  return Column(
                    children: [
                      for (final card in [...cards, ...content]) ...[
                        card,
                        if (card != [...cards, ...content].last)
                          const SizedBox(height: 10),
                      ],
                    ],
                  );
                }

                return Row(
                  children: [
                    for (final card in [...cards, ...content]) ...[
                      Expanded(child: card),
                      if (card != [...cards, ...content].last)
                        const SizedBox(width: 10),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _CalendarMessage(
              icon: Icons.info_outline_rounded,
              text:
                  '${config.title}은 아직 거래 API와 계좌 연동을 연결하지 않았고, 화면 자리만 먼저 준비했습니다.',
              color: config.color,
            ),
          ],
        ),
      ),
    );
  }
}

enum _StockTradingMarket { domestic, overseas }

class _StockTradingMarketTabs extends StatelessWidget {
  const _StockTradingMarketTabs({
    required this.selected,
    required this.onChanged,
  });

  final _StockTradingMarket selected;
  final ValueChanged<_StockTradingMarket> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _stockSurfaceMutedColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stockPanelBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StockTradingMarketTabButton(
              selected: selected == _StockTradingMarket.domestic,
              icon: Icons.account_balance_rounded,
              title: '국내 주식',
              subtitle: 'KRX · KOSPI/KOSDAQ',
              onTap: () => onChanged(_StockTradingMarket.domestic),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _StockTradingMarketTabButton(
              selected: selected == _StockTradingMarket.overseas,
              icon: Icons.public_rounded,
              title: '해외 주식',
              subtitle: 'NASDAQ · NYSE',
              onTap: () => onChanged(_StockTradingMarket.overseas),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingMarketTabButton extends StatelessWidget {
  const _StockTradingMarketTabButton({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? KangColors.ink : KangColors.slate;
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      elevation: selected ? 1 : 0,
      shadowColor: KangColors.ink.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTradingMarketHeader extends StatelessWidget {
  const _StockTradingMarketHeader({required this.config});

  final _StockTradingMarketConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: config.color.withValues(alpha: 0.14)),
        boxShadow: _stockInnerShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(config.icon, color: config.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.title,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  config.description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(text: config.badge, color: config.color),
        ],
      ),
    );
  }
}

class _StockTradingMarketConfig {
  const _StockTradingMarketConfig({
    required this.title,
    required this.description,
    required this.badge,
    required this.icon,
    required this.color,
    required this.balanceTitle,
    required this.balanceValue,
    required this.items,
  });

  final String title;
  final String description;
  final String badge;
  final IconData icon;
  final Color color;
  final String balanceTitle;
  final String balanceValue;
  final List<_StockTradingMarketItem> items;

  static _StockTradingMarketConfig byMarket(_StockTradingMarket market) {
    return switch (market) {
      _StockTradingMarket.domestic => const _StockTradingMarketConfig(
        title: '국내 주식',
        description: '원화 기준 관심종목, 국내 주문, 체결 현황을 배치할 영역입니다.',
        badge: 'KRW',
        icon: Icons.account_balance_rounded,
        color: Color(0xFF2563EB),
        balanceTitle: '보유/잔고',
        balanceValue: '원화 기준',
        items: [
          _StockTradingMarketItem(
            icon: Icons.star_border_rounded,
            title: '관심종목',
            value: 'KOSPI · KOSDAQ',
          ),
          _StockTradingMarketItem(
            icon: Icons.price_change_outlined,
            title: '주문 패널',
            value: '매수 · 매도',
          ),
          _StockTradingMarketItem(
            icon: Icons.receipt_long_outlined,
            title: '체결 현황',
            value: '국내 주문',
          ),
        ],
      ),
      _StockTradingMarket.overseas => const _StockTradingMarketConfig(
        title: '해외 주식',
        description: '달러 기준 관심종목, 해외 주문, 환율/잔고를 배치할 영역입니다.',
        badge: 'USD',
        icon: Icons.public_rounded,
        color: Color(0xFF0F766E),
        balanceTitle: '환율/잔고',
        balanceValue: '달러 기준',
        items: [
          _StockTradingMarketItem(
            icon: Icons.star_border_rounded,
            title: '관심종목',
            value: 'NASDAQ · NYSE',
          ),
          _StockTradingMarketItem(
            icon: Icons.price_change_outlined,
            title: '주문 패널',
            value: 'Buy · Sell',
          ),
          _StockTradingMarketItem(
            icon: Icons.receipt_long_outlined,
            title: '체결 현황',
            value: '해외 주문',
          ),
        ],
      ),
    };
  }
}

class _StockTradingMarketItem {
  const _StockTradingMarketItem({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;
}

class _StockTradingReadyItem extends StatelessWidget {
  const _StockTradingReadyItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _stockSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12)),
        boxShadow: _stockInnerShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketCapCompanyTile extends StatelessWidget {
  const _MarketCapCompanyTile({required this.company, required this.color});

  final MarketCapCompany company;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final change = company.dailyChangePercent;
    final changeColor = change == null
        ? KangColors.slate
        : change >= 0
        ? KangColors.mintDeep
        : Colors.red.shade600;
    final rankAccent = company.rank <= 3 ? KangColors.mintDeep : color;
    final details = [
      company.country,
      company.sector,
      company.industry,
    ].where((value) => value.isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.92)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.055),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: rankAccent.withValues(alpha: 0.82),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rankAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: rankAccent.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Text(
                        '#${company.rank}',
                        style: TextStyle(
                          color: rankAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            company.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: KangColors.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              height: 1.18,
                            ),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              details,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: KangColors.slate,
                                    height: 1.35,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(text: company.symbol, color: rankAccent),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MarketCapMetric(
                      icon: Icons.account_balance_wallet_outlined,
                      label: '시가총액',
                      value: _formatUsdCompact(company.marketCap),
                      accent: rankAccent,
                    ),
                    _MarketCapMetric(
                      icon: Icons.payments_outlined,
                      label: '주가',
                      value: _formatUsdPrice(company.price),
                      accent: KangColors.royalPurple,
                    ),
                    _MarketCapMetric(
                      icon: change == null || change >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      label: '일일변동',
                      value: _formatSignedPercent(change),
                      valueColor: changeColor,
                      accent: changeColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketCapMetric extends StatelessWidget {
  const _MarketCapMetric({
    required this.label,
    required this.value,
    this.icon,
    this.accent = KangColors.mintDeep,
    this.valueColor = KangColors.ink,
  });

  final IconData? icon;
  final String label;
  final String value;
  final Color accent;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.92)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: accent, size: 15),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialInfoFeaturePanel extends StatefulWidget {
  const _FinancialInfoFeaturePanel({required this.module});

  final _HomeModule module;

  @override
  State<_FinancialInfoFeaturePanel> createState() =>
      _FinancialInfoFeaturePanelState();
}

class _FinancialInfoFeaturePanelState
    extends State<_FinancialInfoFeaturePanel> {
  final FinancialMarketApi _financialMarketApi = FinancialMarketApi();
  late Future<FinancialMarketsDataset> _future;

  @override
  void initState() {
    super.initState();
    _future = _financialMarketApi.loadMarkets();
  }

  void _refresh() {
    setState(() {
      _future = _financialMarketApi.loadMarkets();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.82)),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<FinancialMarketsDataset>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final dataset = snapshot.data;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.query_stats_rounded,
                      color: widget.module.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '금융정보 대시보드',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: '금융정보 새로고침',
                      icon: const Icon(Icons.refresh_rounded),
                      color: widget.module.accent,
                      onPressed: loading ? null : _refresh,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading)
                  const _CalendarMessage(
                    icon: Icons.cloud_sync_outlined,
                    text: '금리, 환율, 선물 데이터를 불러오고 있습니다.',
                    color: KangColors.slate,
                  )
                else if (snapshot.hasError || dataset == null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CalendarMessage(
                        icon: Icons.error_outline_rounded,
                        text:
                            snapshot.error?.toString() ??
                            '금융정보 데이터를 불러오지 못했습니다.',
                        color: Colors.red,
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('다시 조회'),
                          onPressed: _refresh,
                        ),
                      ),
                    ],
                  )
                else
                  _FinancialDashboard(
                    dataset: dataset,
                    color: widget.module.accent,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FinancialDashboard extends StatelessWidget {
  const _FinancialDashboard({required this.dataset, required this.color});

  final FinancialMarketsDataset dataset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tenYear = dataset.treasuryRate('10Y');
    final tenTwoSpread = dataset.treasurySpread('10Y-2Y');
    final usdKrw = dataset.exchangeRate('USD/KRW');
    final nasdaqFuture = dataset.futureQuote('NQ=F');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FinancialMarketHero(
          dataset: dataset,
          tenYear: tenYear,
          tenTwoSpread: tenTwoSpread,
          usdKrw: usdKrw,
          nasdaqFuture: nasdaqFuture,
          color: color,
        ),
        const SizedBox(height: 12),
        _UniversitySourceNote(
          color: color,
          title: 'U.S. Treasury · Yahoo Finance Chart Data',
          description:
              '환율과 선물은 1분 차트 quote 기준으로 전일 대비 등락을 표시합니다. '
              '미국채 공식 금리는 Treasury 일일 feed 기준이며 전일 대비 bp를 함께 보여줍니다.',
        ),
        if (dataset.hasErrors) ...[
          const SizedBox(height: 12),
          _CalendarMessage(
            icon: Icons.warning_amber_rounded,
            text: '일부 데이터 소스 오류: ${dataset.errors.join(' · ')}',
            color: Colors.orange.shade700,
          ),
        ],
        const SizedBox(height: 16),
        _FinancialSectionHeader(
          icon: Icons.account_balance_outlined,
          count: dataset.treasuryRates.length,
          color: color,
          title: '미국채 수익률',
          subtitle: dataset.summary.treasuryDate,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final rate in dataset.treasuryRates)
              _TreasuryRateTile(rate: rate, color: color),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final spread in dataset.treasurySpreads)
              _SpreadChip(spread: spread, color: color),
          ],
        ),
        const SizedBox(height: 18),
        _FinancialSectionHeader(
          icon: Icons.currency_exchange_rounded,
          count: dataset.exchangeRates.length,
          color: color,
          title: '실시간 주요 환율',
          subtitle: _formatMarketCapDate(dataset.summary.exchangeRateDate),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: dataset.exchangeRates.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: compact ? 2 : 4,
                mainAxisExtent: compact ? 162 : 154,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                return _ExchangeRateTile(
                  rate: dataset.exchangeRates[index],
                  color: color,
                );
              },
            );
          },
        ),
        const SizedBox(height: 18),
        _FinancialSectionHeader(
          icon: Icons.show_chart_rounded,
          count: dataset.futures.length,
          color: color,
          title: '실시간 선물·매크로',
          subtitle: 'Yahoo Finance',
        ),
        const SizedBox(height: 8),
        for (final quote in dataset.futures)
          _FinancialFutureTile(quote: quote, color: color),
      ],
    );
  }
}

class _FinancialMarketHero extends StatelessWidget {
  const _FinancialMarketHero({
    required this.dataset,
    required this.tenYear,
    required this.tenTwoSpread,
    required this.usdKrw,
    required this.nasdaqFuture,
    required this.color,
  });

  final FinancialMarketsDataset dataset;
  final TreasuryRate? tenYear;
  final TreasurySpread? tenTwoSpread;
  final ExchangeRate? usdKrw;
  final MarketFutureQuote? nasdaqFuture;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KangColors.deepPurple,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.mint.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.monitor_heart_outlined,
                  color: KangColors.mint,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '금융정보 라이브 보드',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '업데이트 ${_formatMarketCapDate(dataset.fetchedAt)} · ${dataset.cacheSeconds}초 캐시',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              _FinancialLiveBadge(color: KangColors.mint),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _FinancialHeroMetric(
                    width: narrow ? double.infinity : 150,
                    label: '미 10년물',
                    value: _formatRatePercent(tenYear?.rate),
                    changeText: _formatBasisPointChange(tenYear?.change),
                    changeValue: tenYear?.change,
                    icon: Icons.account_balance_outlined,
                    accent: color,
                  ),
                  _FinancialHeroMetric(
                    width: narrow ? double.infinity : 150,
                    label: '10Y-2Y',
                    value: _formatSpreadPercent(tenTwoSpread?.value),
                    changeText: '스프레드',
                    changeValue: tenTwoSpread?.value,
                    icon: Icons.timeline_rounded,
                    accent: KangColors.orchid,
                  ),
                  _FinancialHeroMetric(
                    width: narrow ? double.infinity : 150,
                    label: 'USD/KRW',
                    value: _formatFxRate(usdKrw?.rate),
                    changeText:
                        '${_formatFxChange(usdKrw?.change, usdKrw?.rate)} · ${_formatSignedPercent(usdKrw?.changePercent)}',
                    changeValue: usdKrw?.change,
                    icon: Icons.currency_exchange_rounded,
                    accent: KangColors.mint,
                  ),
                  _FinancialHeroMetric(
                    width: narrow ? double.infinity : 150,
                    label: 'Nasdaq 선물',
                    value: _formatMarketQuotePrice(nasdaqFuture?.price),
                    changeText: _formatSignedPercent(
                      nasdaqFuture?.changePercent,
                    ),
                    changeValue: nasdaqFuture?.changePercent,
                    icon: Icons.show_chart_rounded,
                    accent: KangColors.mintDeep,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FinancialHeroMetric extends StatelessWidget {
  const _FinancialHeroMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.changeText,
    required this.changeValue,
    required this.icon,
    required this.accent,
  });

  final double width;
  final String label;
  final String value;
  final String changeText;
  final double? changeValue;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final constrainedWidth = width.isFinite ? width : null;
    return SizedBox(
      width: constrainedWidth,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 17),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.74),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            _FinancialChangePill(value: changeValue, text: changeText),
          ],
        ),
      ),
    );
  }
}

class _FinancialSectionHeader extends StatelessWidget {
  const _FinancialSectionHeader({
    required this.icon,
    required this.count,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final int count;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                ),
            ],
          ),
        ),
        _StatusPill(text: '$count개', color: color),
      ],
    );
  }
}

class _FinancialLiveBadge extends StatelessWidget {
  const _FinancialLiveBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialChangePill extends StatelessWidget {
  const _FinancialChangePill({required this.value, required this.text});

  final double? value;
  final String text;

  @override
  Widget build(BuildContext context) {
    final neutral = value == null || value!.abs() < 0.0000001;
    final positive = (value ?? 0) > 0;
    final color = neutral
        ? KangColors.slate
        : positive
        ? KangColors.mintDeep
        : Colors.red.shade600;
    final icon = neutral
        ? Icons.remove_rounded
        : positive
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TreasuryRateTile extends StatelessWidget {
  const _TreasuryRateTile({required this.rate, required this.color});

  final TreasuryRate rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 122,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rate.maturity,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              Icon(Icons.account_balance_outlined, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            rate.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
          ),
          const SizedBox(height: 9),
          Text(
            _formatRatePercent(rate.rate),
            style: const TextStyle(
              color: KangColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _FinancialChangePill(
            value: rate.change,
            text: _formatBasisPointChange(rate.change),
          ),
        ],
      ),
    );
  }
}

class _SpreadChip extends StatelessWidget {
  const _SpreadChip({required this.spread, required this.color});

  final TreasurySpread spread;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = spread.value;
    final valueColor = (value ?? 0) >= 0 ? color : Colors.red.shade600;

    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stacked_line_chart_rounded, color: color, size: 16),
          const SizedBox(width: 7),
          Text(
            spread.code,
            style: const TextStyle(
              color: KangColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatSpreadPercent(value),
            style: TextStyle(color: valueColor, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ExchangeRateTile extends StatelessWidget {
  const _ExchangeRateTile({required this.rate, required this.color});

  final ExchangeRate rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final changeValue = rate.change;
    final updateText = rate.marketTime.isEmpty
        ? rate.date
        : _formatMarketCapDate(rate.marketTime);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rate.pair,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              _FinancialLiveBadge(color: color),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            _formatFxRate(rate.rate),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KangColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _FinancialChangePill(
            value: changeValue,
            text:
                '${_formatFxChange(rate.change, rate.rate)} · ${_formatSignedPercent(rate.changePercent)}',
          ),
          const Spacer(),
          Divider(height: 13, color: KangColors.line.withValues(alpha: 0.72)),
          Row(
            children: [
              Expanded(
                child: Text(
                  rate.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                updateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: KangColors.slate,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '전일 ${_formatFxRate(rate.previousRate)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
          ),
        ],
      ),
    );
  }
}

class _FinancialFutureTile extends StatelessWidget {
  const _FinancialFutureTile({required this.quote, required this.color});

  final MarketFutureQuote quote;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final changeColor = (quote.changePercent ?? 0) >= 0
        ? KangColors.mintDeep
        : Colors.red.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.show_chart_rounded, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        quote.symbol,
                        quote.exchange,
                        _formatMarketCapDate(quote.marketTime),
                      ].where((value) => value.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _FinancialChangePill(
                value: quote.changePercent,
                text: _formatSignedPercent(quote.changePercent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MarketCapMetric(
                label: '가격',
                value: _formatMarketQuotePrice(quote.price),
              ),
              _MarketCapMetric(
                label: '변동',
                value: _formatSignedNumber(quote.change),
                valueColor: changeColor,
              ),
              _MarketCapMetric(
                label: '변동률',
                value: _formatSignedPercent(quote.changePercent),
                valueColor: changeColor,
              ),
              _MarketCapMetric(
                label: '전일종가',
                value: _formatMarketQuotePrice(quote.previousClose),
              ),
              _MarketCapMetric(label: '구분', value: quote.group),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubwayFeaturePanel extends StatefulWidget {
  const _SubwayFeaturePanel({required this.module});

  final _HomeModule module;

  @override
  State<_SubwayFeaturePanel> createState() => _SubwayFeaturePanelState();
}

class _SubwayFeaturePanelState extends State<_SubwayFeaturePanel> {
  final SubwayApi _subwayApi = SubwayApi();
  final TextEditingController _stationController = TextEditingController(
    text: '야탑',
  );

  late Future<SubwayOverviewDataset> _future;
  String _station = '야탑';
  final String _line = '수인분당선';
  String? _directionFilter;
  bool _showTimetable = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _stationController.dispose();
    super.dispose();
  }

  Future<SubwayOverviewDataset> _load() {
    return _subwayApi.loadOverview(station: _station, line: _line);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  void _submitSearch() {
    final station = _stationController.text.trim().replaceAll('역', '');
    if (station.isEmpty) {
      return;
    }
    setState(() {
      _station = station;
      _directionFilter = null;
      _showTimetable = false;
      _future = _load();
    });
  }

  void _selectDirection(String? direction) {
    setState(() {
      _directionFilter = _directionFilter == direction ? null : direction;
    });
  }

  void _selectRealtimeMode(bool showTimetable) {
    setState(() {
      _showTimetable = showTimetable;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.86)),
        boxShadow: [
          BoxShadow(
            color: widget.module.accent.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<SubwayOverviewDataset>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final dataset = snapshot.data;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.train_rounded, color: widget.module.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '지하철 라이브',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: '지하철 정보 새로고침',
                      icon: const Icon(Icons.refresh_rounded),
                      color: widget.module.accent,
                      onPressed: loading ? null : _refresh,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SubwaySearchBar(
                  stationController: _stationController,
                  color: widget.module.accent,
                  onSubmitted: _submitSearch,
                ),
                const SizedBox(height: 14),
                if (loading)
                  const _CalendarMessage(
                    icon: Icons.cloud_sync_outlined,
                    text: '서울시 실시간 지하철 정보를 불러오고 있습니다.',
                    color: KangColors.slate,
                  )
                else if (snapshot.hasError || dataset == null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CalendarMessage(
                        icon: Icons.error_outline_rounded,
                        text:
                            snapshot.error?.toString() ?? '지하철 정보를 불러오지 못했습니다.',
                        color: Colors.red,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('다시 조회'),
                        onPressed: _refresh,
                      ),
                    ],
                  )
                else
                  _SubwayDashboard(
                    dataset: dataset,
                    color: widget.module.accent,
                    directionFilter: _directionFilter,
                    showTimetable: _showTimetable,
                    onDirectionSelected: _selectDirection,
                    onModeChanged: _selectRealtimeMode,
                    onRefresh: _refresh,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SubwaySearchBar extends StatelessWidget {
  const _SubwaySearchBar({
    required this.stationController,
    required this.color,
    required this.onSubmitted,
  });

  final TextEditingController stationController;
  final Color color;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            '역 검색',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: KangColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.28)),
                boxShadow: [
                  BoxShadow(
                    color: KangColors.deepPurple.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: TextField(
                controller: stationController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSubmitted(),
                decoration: InputDecoration(
                  icon: Icon(Icons.search_rounded, color: color),
                  hintText: '예: 강남, 야탑, 모란',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                style: const TextStyle(
                  color: KangColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: '조회',
            icon: const Icon(Icons.search_rounded),
            style: IconButton.styleFrom(backgroundColor: color),
            onPressed: onSubmitted,
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SubwayLineSelector extends StatelessWidget {
  const _SubwayLineSelector({
    required this.lines,
    required this.selectedLine,
    required this.expressOnly,
    required this.color,
    required this.onSelected,
    required this.onExpressChanged,
  });

  final List<String> lines;
  final String selectedLine;
  final bool expressOnly;
  final Color color;
  final ValueChanged<String> onSelected;
  final ValueChanged<bool> onExpressChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SubwayLineChoiceChip(
                line: line,
                selected:
                    line == selectedLine ||
                    (line == '전체 노선' && selectedLine.isEmpty),
                color: line == '전체 노선'
                    ? color
                    : _subwayColorForLine(line, color),
                onTap: () => onSelected(line),
              ),
            ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: KangColors.line,
          ),
          _SubwayLineChoiceChip(
            line: '급행',
            selected: expressOnly,
            color: Colors.red.shade600,
            onTap: () => onExpressChanged(!expressOnly),
          ),
        ],
      ),
    );
  }
}

class _SubwayLineChoiceChip extends StatelessWidget {
  const _SubwayLineChoiceChip({
    required this.line,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String line;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compactLine = RegExp(r'^\d호선$').hasMatch(line);
    final wideChip = !compactLine;
    final label = compactLine ? line.replaceAll('호선', '') : line;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 34,
        constraints: BoxConstraints(minWidth: wideChip ? 72 : 34),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: wideChip ? 12 : 0),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          shape: wideChip ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: wideChip ? BorderRadius.circular(999) : null,
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.28),
            width: 1.4,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : wideChip
                ? color
                : KangColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SubwayDashboard extends StatelessWidget {
  const _SubwayDashboard({
    required this.dataset,
    required this.color,
    required this.directionFilter,
    required this.showTimetable,
    required this.onDirectionSelected,
    required this.onModeChanged,
    required this.onRefresh,
  });

  final SubwayOverviewDataset dataset;
  final Color color;
  final String? directionFilter;
  final bool showTimetable;
  final ValueChanged<String?> onDirectionSelected;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final subwayColor = dataset.arrivals.isNotEmpty
        ? _colorFromHex(dataset.arrivals.first.lineColor, color)
        : _colorFromHex(dataset.summary.lineColor, color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dataset.hasErrors) ...[
          _CalendarMessage(
            icon: Icons.warning_amber_rounded,
            text: '일부 지하철 데이터 오류: ${dataset.errors.join(' · ')}',
            color: Colors.orange.shade700,
          ),
          const SizedBox(height: 12),
        ],
        _SubwayBottomPanel(
          dataset: dataset,
          color: subwayColor,
          directionFilter: directionFilter,
          showTimetable: showTimetable,
          onDirectionSelected: onDirectionSelected,
          onModeChanged: onModeChanged,
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}

// ignore: unused_element
class _SubwayMapExperience extends StatelessWidget {
  const _SubwayMapExperience({
    required this.dataset,
    required this.color,
    required this.lineScope,
    required this.expressOnly,
  });

  final SubwayOverviewDataset dataset;
  final Color color;
  final String lineScope;
  final bool expressOnly;

  @override
  Widget build(BuildContext context) {
    final primaryArrival = dataset.arrivals.isNotEmpty
        ? dataset.arrivals.first
        : null;
    final highlightAll = lineScope == '전체 노선';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final height = compact ? 500.0 : 450.0;
        return Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFFDFEFF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KangColors.line),
            boxShadow: [
              BoxShadow(
                color: KangColors.deepPurple.withValues(alpha: 0.07),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SubwayMapPainter(
                    activeLine: highlightAll ? dataset.summary.line : lineScope,
                    activeStation: dataset.summary.station,
                    highlightAll: highlightAll,
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                child: _SubwayMapBadge(
                  icon: Icons.map_outlined,
                  text: '수도권 노선도',
                  color: color,
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: _FinancialLiveBadge(color: color),
              ),
              Center(
                child: _SubwayRouteOverlay(
                  station: dataset.summary.station,
                  line: dataset.summary.line,
                  destination: primaryArrival?.destination ?? '',
                  expressOnly: expressOnly,
                  color: color,
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 18,
                child: _SubwayCurrentStationPill(
                  dataset: dataset,
                  arrival: primaryArrival,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SubwayMapBadge extends StatelessWidget {
  const _SubwayMapBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KangColors.line),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: KangColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubwayRouteOverlay extends StatelessWidget {
  const _SubwayRouteOverlay({
    required this.station,
    required this.line,
    required this.destination,
    required this.expressOnly,
    required this.color,
  });

  final String station;
  final String line;
  final String destination;
  final bool expressOnly;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 226,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: KangColors.ink.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _SubwayRouteNode(
                icon: Icons.location_on_rounded,
                label: '출발',
                color: KangColors.mintDeep,
              ),
              Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.16)),
              ),
              _SubwayRouteNode(
                icon: Icons.location_on_rounded,
                label: '경유',
                color: KangColors.slate,
              ),
              Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.16)),
              ),
              _SubwayRouteNode(
                icon: Icons.location_on_rounded,
                label: '도착',
                color: Colors.deepOrange,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              [
                '$station역',
                line,
                if (expressOnly) '급행',
                if (destination.isNotEmpty) '$destination행',
              ].join(' · '),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubwayRouteNode extends StatelessWidget {
  const _SubwayRouteNode({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _SubwayCurrentStationPill extends StatelessWidget {
  const _SubwayCurrentStationPill({
    required this.dataset,
    required this.arrival,
    required this.color,
  });

  final SubwayOverviewDataset dataset;
  final SubwayArrival? arrival;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final destination = arrival?.destination ?? '';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          _SubwayLineBadge(line: dataset.summary.line, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${dataset.summary.station}역',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KangColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            destination.isEmpty ? '실시간' : '$destination행',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _SubwayBottomPanel extends StatelessWidget {
  const _SubwayBottomPanel({
    required this.dataset,
    required this.color,
    required this.directionFilter,
    required this.showTimetable,
    required this.onDirectionSelected,
    required this.onModeChanged,
    required this.onRefresh,
  });

  final SubwayOverviewDataset dataset;
  final Color color;
  final String? directionFilter;
  final bool showTimetable;
  final ValueChanged<String?> onDirectionSelected;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    const leftTarget = '상행';
    const rightTarget = '하행';
    final visibleArrivals = directionFilter == null
        ? dataset.arrivals
        : dataset.arrivals
              .where((arrival) => _isSubwayDirection(arrival, directionFilter!))
              .toList();
    final groupedArrivals = _groupSubwayArrivalsByDirection(visibleArrivals);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 46,
              height: 4,
              decoration: BoxDecoration(
                color: KangColors.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SubwayRouteBar(
            station: dataset.summary.station,
            left: leftTarget,
            right: rightTarget,
            selectedDirection: directionFilter,
            color: color,
            onLeftTap: () => onDirectionSelected(leftTarget),
            onCenterTap: () => onDirectionSelected(null),
            onRightTap: () => onDirectionSelected(rightTarget),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SubwaySegment(
                text: '실시간',
                selected: !showTimetable,
                color: color,
                onTap: () => onModeChanged(false),
              ),
              const SizedBox(width: 6),
              _SubwaySegment(
                text: '시간표',
                selected: showTimetable,
                color: color,
                onTap: () => onModeChanged(true),
              ),
              const Spacer(),
              Text(
                _formatMarketCapDate(dataset.fetchedAt),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: KangColors.slate),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '도착정보 새로고침',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                color: KangColors.slate,
                iconSize: 20,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (visibleArrivals.isEmpty)
            _CalendarMessage(
              icon: Icons.train_outlined,
              text: directionFilter == null
                  ? '현재 표시할 도착 정보가 없습니다.'
                  : '$directionFilter방향 도착 정보가 없습니다. 가운데 역 이름을 누르면 전체로 돌아갑니다.',
              color: KangColors.slate,
            )
          else if (showTimetable)
            _SubwayTimetablePreview(arrivals: visibleArrivals, color: color)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: math.min(groupedArrivals.length, 2),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: compact ? 2 : 4,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final group = groupedArrivals[index];
                    return _SubwayDirectionArrivalCard(
                      target: group.key,
                      arrivals: group.value,
                      color: color,
                      onTap: () => onDirectionSelected(group.key),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SubwayRouteBar extends StatelessWidget {
  const _SubwayRouteBar({
    required this.station,
    required this.left,
    required this.right,
    required this.selectedDirection,
    required this.color,
    required this.onLeftTap,
    required this.onCenterTap,
    required this.onRightTap,
  });

  final String station;
  final String left;
  final String right;
  final String? selectedDirection;
  final Color color;
  final VoidCallback onLeftTap;
  final VoidCallback onCenterTap;
  final VoidCallback onRightTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(999),
              ),
              onTap: onLeftTap,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: selectedDirection == left
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(999),
                  ),
                ),
                child: _SubwayRouteBarText(
                  text: left.isEmpty ? '출발' : left,
                  align: TextAlign.center,
                  icon: Icons.chevron_left_rounded,
                ),
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onCenterTap,
            child: Container(
              height: 46,
              constraints: const BoxConstraints(minWidth: 142),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_vert_rounded, color: color, size: 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      station,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(999),
              ),
              onTap: onRightTap,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: selectedDirection == right
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(999),
                  ),
                ),
                child: _SubwayRouteBarText(
                  text: right.isEmpty ? '도착' : right,
                  align: TextAlign.center,
                  trailing: Icons.chevron_right_rounded,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubwayRouteBarText extends StatelessWidget {
  const _SubwayRouteBarText({
    required this.text,
    required this.align,
    this.icon,
    this.trailing,
  });

  final String text;
  final TextAlign align;
  final IconData? icon;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) Icon(icon, color: Colors.white, size: 19),
        Flexible(
          child: Text(
            text,
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null) Icon(trailing, color: Colors.white, size: 19),
      ],
    );
  }
}

class _SubwaySegment extends StatelessWidget {
  const _SubwaySegment({
    required this.text,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? color : KangColors.line),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? color : KangColors.slate,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SubwayDirectionArrivalCard extends StatelessWidget {
  const _SubwayDirectionArrivalCard({
    required this.target,
    required this.arrivals,
    required this.color,
    required this.onTap,
  });

  final String target;
  final List<SubwayArrival> arrivals;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lineColor = arrivals.isNotEmpty
        ? _colorFromHex(arrivals.first.lineColor, color)
        : color;
    final rows = arrivals.take(2).toList(growable: false);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KangColors.line),
          boxShadow: [
            BoxShadow(
              color: lineColor.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatSubwayDirectionTitle(target),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: KangColors.slate),
              ],
            ),
            const Divider(height: 18),
            for (final arrival in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _SubwayArrivalLine(arrival: arrival, color: lineColor),
              ),
            if (rows.length < 2)
              Text(
                '다음 열차 확인 중',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubwayArrivalLine extends StatelessWidget {
  const _SubwayArrivalLine({required this.arrival, required this.color});

  final SubwayArrival arrival;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final position = arrival.arrivalDetail.isNotEmpty
        ? arrival.arrivalDetail
        : arrival.status;
    return Row(
      children: [
        Expanded(
          child: Text(
            position,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: KangColors.slate),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatSubwayArrivalEta(arrival),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _subwayArrivalEtaColor(arrival, color),
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _SubwayTimetablePreview extends StatelessWidget {
  const _SubwayTimetablePreview({required this.arrivals, required this.color});

  final List<SubwayArrival> arrivals;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KangColors.surfaceWarm.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        children: [
          for (final arrival in arrivals.take(6))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _SubwayLineBadge(
                    line: arrival.line.isEmpty ? '-' : arrival.line,
                    color: _colorFromHex(arrival.lineColor, color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        if (arrival.destination.isNotEmpty)
                          '${arrival.destination}행',
                        if (arrival.arrivalDetail.isNotEmpty)
                          arrival.arrivalDetail,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatSubwayArrivalEta(arrival),
                    style: TextStyle(
                      color: _subwayArrivalEtaColor(arrival, color),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SubwayRouteSpec {
  const _SubwayRouteSpec({
    required this.line,
    required this.fallback,
    required this.points,
    required this.labels,
  });

  final String line;
  final Color fallback;
  final List<Offset> points;
  final Map<String, Offset> labels;
}

class _SubwayMapPainter extends CustomPainter {
  _SubwayMapPainter({
    required this.activeLine,
    required this.activeStation,
    required this.highlightAll,
  });

  final String activeLine;
  final String activeStation;
  final bool highlightAll;

  static const List<_SubwayRouteSpec> _routes = [
    _SubwayRouteSpec(
      line: '1호선',
      fallback: Color(0xFF0052A4),
      points: [
        Offset(0.05, 0.66),
        Offset(0.20, 0.62),
        Offset(0.36, 0.58),
        Offset(0.49, 0.51),
        Offset(0.66, 0.46),
        Offset(0.94, 0.40),
      ],
      labels: {
        '서울': Offset(0.22, 0.62),
        '시청': Offset(0.31, 0.59),
        '종로3가': Offset(0.43, 0.54),
        '청량리': Offset(0.72, 0.44),
      },
    ),
    _SubwayRouteSpec(
      line: '2호선',
      fallback: Color(0xFF00A84D),
      points: [
        Offset(0.18, 0.43),
        Offset(0.32, 0.36),
        Offset(0.52, 0.34),
        Offset(0.69, 0.41),
        Offset(0.74, 0.56),
        Offset(0.59, 0.68),
        Offset(0.38, 0.67),
        Offset(0.23, 0.58),
        Offset(0.18, 0.43),
      ],
      labels: {
        '홍대입구': Offset(0.24, 0.55),
        '왕십리': Offset(0.64, 0.39),
        '잠실': Offset(0.73, 0.48),
        '선릉': Offset(0.66, 0.58),
        '강남': Offset(0.57, 0.66),
        '사당': Offset(0.40, 0.67),
      },
    ),
    _SubwayRouteSpec(
      line: '3호선',
      fallback: Color(0xFFEF7C1C),
      points: [
        Offset(0.41, 0.08),
        Offset(0.45, 0.22),
        Offset(0.48, 0.36),
        Offset(0.52, 0.50),
        Offset(0.56, 0.65),
        Offset(0.60, 0.87),
      ],
      labels: {
        '경복궁': Offset(0.45, 0.22),
        '충무로': Offset(0.50, 0.43),
        '고속터미널': Offset(0.54, 0.58),
        '양재': Offset(0.58, 0.72),
      },
    ),
    _SubwayRouteSpec(
      line: '4호선',
      fallback: Color(0xFF00A5DE),
      points: [
        Offset(0.15, 0.12),
        Offset(0.28, 0.27),
        Offset(0.40, 0.41),
        Offset(0.52, 0.55),
        Offset(0.63, 0.70),
        Offset(0.77, 0.88),
      ],
      labels: {
        '혜화': Offset(0.31, 0.30),
        '명동': Offset(0.43, 0.45),
        '사당': Offset(0.65, 0.72),
      },
    ),
    _SubwayRouteSpec(
      line: '5호선',
      fallback: Color(0xFF996CAC),
      points: [
        Offset(0.06, 0.30),
        Offset(0.25, 0.29),
        Offset(0.44, 0.28),
        Offset(0.61, 0.29),
        Offset(0.82, 0.32),
        Offset(0.96, 0.36),
      ],
      labels: {
        '여의도': Offset(0.22, 0.29),
        '광화문': Offset(0.40, 0.28),
        '왕십리': Offset(0.66, 0.30),
        '오금': Offset(0.90, 0.35),
      },
    ),
    _SubwayRouteSpec(
      line: '6호선',
      fallback: Color(0xFFCD7C2F),
      points: [
        Offset(0.08, 0.22),
        Offset(0.23, 0.19),
        Offset(0.40, 0.18),
        Offset(0.58, 0.20),
        Offset(0.78, 0.24),
        Offset(0.92, 0.28),
      ],
      labels: {
        '합정': Offset(0.23, 0.19),
        '이태원': Offset(0.50, 0.19),
        '약수': Offset(0.62, 0.21),
      },
    ),
    _SubwayRouteSpec(
      line: '7호선',
      fallback: Color(0xFF747F00),
      points: [
        Offset(0.79, 0.12),
        Offset(0.75, 0.28),
        Offset(0.71, 0.44),
        Offset(0.69, 0.60),
        Offset(0.66, 0.78),
        Offset(0.62, 0.92),
      ],
      labels: {
        '건대입구': Offset(0.74, 0.31),
        '고속터미널': Offset(0.69, 0.60),
        '이수': Offset(0.65, 0.80),
      },
    ),
    _SubwayRouteSpec(
      line: '8호선',
      fallback: Color(0xFFE6186C),
      points: [
        Offset(0.76, 0.52),
        Offset(0.84, 0.59),
        Offset(0.91, 0.69),
        Offset(0.95, 0.82),
      ],
      labels: {
        '잠실': Offset(0.77, 0.53),
        '가락시장': Offset(0.86, 0.62),
        '모란': Offset(0.94, 0.80),
      },
    ),
    _SubwayRouteSpec(
      line: '9호선',
      fallback: Color(0xFFBDB092),
      points: [
        Offset(0.08, 0.74),
        Offset(0.25, 0.73),
        Offset(0.42, 0.70),
        Offset(0.56, 0.64),
        Offset(0.72, 0.60),
        Offset(0.92, 0.58),
      ],
      labels: {
        '김포공항': Offset(0.12, 0.74),
        '여의도': Offset(0.29, 0.73),
        '신논현': Offset(0.51, 0.66),
        '선정릉': Offset(0.65, 0.62),
        '종합운동장': Offset(0.80, 0.59),
      },
    ),
    _SubwayRouteSpec(
      line: '신분당선',
      fallback: Color(0xFFD4003B),
      points: [
        Offset(0.49, 0.58),
        Offset(0.55, 0.68),
        Offset(0.61, 0.80),
        Offset(0.68, 0.94),
      ],
      labels: {
        '신논현': Offset(0.50, 0.60),
        '강남': Offset(0.55, 0.68),
        '양재': Offset(0.60, 0.78),
      },
    ),
    _SubwayRouteSpec(
      line: '공항철도',
      fallback: Color(0xFF0090D2),
      points: [
        Offset(0.02, 0.14),
        Offset(0.16, 0.20),
        Offset(0.28, 0.27),
        Offset(0.38, 0.33),
      ],
      labels: {
        '김포공항': Offset(0.13, 0.20),
        '홍대입구': Offset(0.28, 0.27),
        '서울': Offset(0.38, 0.33),
      },
    ),
    _SubwayRouteSpec(
      line: '경의중앙선',
      fallback: Color(0xFF77C4A3),
      points: [
        Offset(0.04, 0.39),
        Offset(0.20, 0.39),
        Offset(0.35, 0.38),
        Offset(0.52, 0.37),
        Offset(0.70, 0.37),
        Offset(0.95, 0.38),
      ],
      labels: {
        '공덕': Offset(0.22, 0.39),
        '용산': Offset(0.40, 0.38),
        '왕십리': Offset(0.68, 0.37),
      },
    ),
    _SubwayRouteSpec(
      line: '수인분당선',
      fallback: Color(0xFFF5A200),
      points: [
        Offset(0.21, 0.86),
        Offset(0.35, 0.78),
        Offset(0.51, 0.70),
        Offset(0.68, 0.62),
        Offset(0.84, 0.54),
      ],
      labels: {
        '수원': Offset(0.23, 0.85),
        '압구정로데오': Offset(0.48, 0.71),
        '선릉': Offset(0.60, 0.66),
        '수서': Offset(0.78, 0.57),
      },
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final backgroundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF5FAFF)],
      ).createShader(rect);
    canvas.drawRect(rect, backgroundPaint);

    final gridPaint = Paint()
      ..color = KangColors.line.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var i = 1; i < 5; i++) {
      final x = size.width * i / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final hasActiveStation = _routes.any(
      (route) => route.labels.containsKey(activeStation),
    );
    for (final route in _routes) {
      _drawRoute(canvas, size, route);
    }
    if (!hasActiveStation && activeStation.isNotEmpty) {
      _drawFloatingStation(canvas, size);
    }
  }

  void _drawRoute(Canvas canvas, Size size, _SubwayRouteSpec route) {
    final isActive = activeLine == route.line;
    final color = _subwayColorForLine(route.line, route.fallback);
    final visibleAsMain = highlightAll || isActive;
    final paint = Paint()
      ..color = color.withValues(
        alpha: visibleAsMain ? (isActive ? 0.98 : 0.82) : 0.28,
      )
      ..strokeWidth = visibleAsMain ? (isActive ? 6.2 : 4.6) : 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(
        route.points.first.dx * size.width,
        route.points.first.dy * size.height,
      );
    for (final point in route.points.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(path, paint);

    final markerPoint = Offset(
      route.points.first.dx * size.width,
      route.points.first.dy * size.height,
    );
    _drawLineMarker(canvas, route.line, markerPoint, color, visibleAsMain);

    for (final entry in route.labels.entries) {
      final point = Offset(
        entry.value.dx * size.width,
        entry.value.dy * size.height,
      );
      final selected = entry.key == activeStation;
      final stationPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = selected
            ? color
            : color.withValues(alpha: visibleAsMain ? 0.78 : 0.34)
        ..strokeWidth = selected ? 3 : 1.8
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(point, selected ? 7.2 : 4.7, stationPaint);
      canvas.drawCircle(point, selected ? 7.2 : 4.7, borderPaint);
      _drawLabel(
        canvas,
        entry.key,
        point.translate(0, selected ? -24 : -18),
        selected
            ? KangColors.ink
            : KangColors.ink.withValues(alpha: visibleAsMain ? 0.70 : 0.42),
        selected,
      );
    }
  }

  void _drawLineMarker(
    Canvas canvas,
    String line,
    Offset center,
    Color color,
    bool emphasized,
  ) {
    final text = switch (line) {
      '공항철도' => 'AREX',
      '경의중앙선' => '경의',
      '수인분당선' => '수인',
      '신분당선' => '신분당',
      _ => line.replaceAll('호선', ''),
    };
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 54);
    final width = math.max(24.0, painter.width + 12);
    final origin = Offset(center.dx - width / 2, center.dy - 26);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.dx, origin.dy, width, 21),
      const Radius.circular(999),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = color.withValues(alpha: emphasized ? 0.94 : 0.46),
    );
    painter.paint(
      canvas,
      Offset(origin.dx + width / 2 - painter.width / 2, origin.dy + 4),
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    bool selected,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: selected ? 12 : 10,
          fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: selected ? 92 : 68);
    final origin = Offset(
      center.dx - painter.width / 2,
      center.dy - painter.height / 2,
    );
    if (selected) {
      final bubble = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          origin.dx - 7,
          origin.dy - 4,
          painter.width + 14,
          painter.height + 8,
        ),
        const Radius.circular(999),
      );
      canvas.drawRRect(
        bubble,
        Paint()..color = Colors.white.withValues(alpha: 0.96),
      );
      canvas.drawRRect(
        bubble,
        Paint()
          ..color = KangColors.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    painter.paint(canvas, origin);
  }

  void _drawFloatingStation(Canvas canvas, Size size) {
    final point = Offset(size.width * 0.50, size.height * 0.56);
    final color = _subwayColorForLine(activeLine, KangColors.deepPurple);
    canvas.drawCircle(
      point,
      8,
      Paint()..color = Colors.white.withValues(alpha: 0.98),
    );
    canvas.drawCircle(
      point,
      8,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    _drawLabel(
      canvas,
      activeStation,
      point.translate(0, -26),
      KangColors.ink,
      true,
    );
  }

  @override
  bool shouldRepaint(covariant _SubwayMapPainter oldDelegate) {
    return oldDelegate.activeLine != activeLine ||
        oldDelegate.activeStation != activeStation ||
        oldDelegate.highlightAll != highlightAll;
  }
}

// ignore: unused_element
class _SubwayHero extends StatelessWidget {
  const _SubwayHero({required this.dataset, required this.color});

  final SubwayOverviewDataset dataset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KangColors.deepPurple,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.train_rounded, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dataset.summary.station}역',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${dataset.summary.line} · ${dataset.cacheSeconds}초 캐시 · 서울시 실시간',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              _FinancialLiveBadge(color: color),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FinancialHeroMetric(
                width: 150,
                label: '도착 정보',
                value: '${dataset.summary.arrivalCount}건',
                changeText: '역 기준',
                changeValue: 0,
                icon: Icons.schedule_rounded,
                accent: color,
              ),
              _FinancialHeroMetric(
                width: 150,
                label: '열차 위치',
                value: '${dataset.summary.trainCount}건',
                changeText: '호선 기준',
                changeValue: 0,
                icon: Icons.route_rounded,
                accent: KangColors.mint,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SubwayFavoriteBar extends StatelessWidget {
  const _SubwayFavoriteBar({
    required this.favorites,
    required this.station,
    required this.line,
    required this.color,
    required this.onSelected,
  });

  final List<SubwayFavoriteStation> favorites;
  final String station;
  final String line;
  final Color color;
  final ValueChanged<SubwayFavoriteStation> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final favorite in favorites)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  Icons.train_outlined,
                  size: 16,
                  color: favorite.station == station && favorite.line == line
                      ? Colors.white
                      : color,
                ),
                label: Text(favorite.label),
                selected: favorite.station == station && favorite.line == line,
                selectedColor: color,
                labelStyle: TextStyle(
                  color: favorite.station == station && favorite.line == line
                      ? Colors.white
                      : KangColors.ink,
                  fontWeight: FontWeight.w800,
                ),
                onSelected: (_) => onSelected(favorite),
              ),
            ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SubwayArrivalTile extends StatelessWidget {
  const _SubwayArrivalTile({required this.arrival, required this.color});

  final SubwayArrival arrival;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final lineColor = _colorFromHex(arrival.lineColor, color);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: lineColor.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SubwayLineBadge(line: arrival.line, color: lineColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      arrival.trainLine.isEmpty
                          ? '${arrival.destination}행'
                          : arrival.trainLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        arrival.direction,
                        if (arrival.trainNo.isNotEmpty) '열차 ${arrival.trainNo}',
                        _formatSubwayTime(arrival.receivedAt),
                      ].where((value) => value.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _FinancialChangePill(
                value: null,
                text: _formatSubwayEta(arrival.etaSeconds),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: lineColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_active_outlined, color: lineColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    arrival.arrivalMessage.isEmpty
                        ? arrival.status
                        : arrival.arrivalMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: lineColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SubwayTrainTile extends StatelessWidget {
  const _SubwayTrainTile({required this.train, required this.color});

  final SubwayTrainPosition train;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final lineColor = _colorFromHex(train.lineColor, color);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SubwayLineBadge(line: train.line, color: lineColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  train.station,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _StatusPill(text: train.status, color: lineColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${train.destination}행',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: KangColors.ink),
          ),
          const Spacer(),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatusPill(text: '열차 ${train.trainNo}', color: color),
              if (train.isExpress) _StatusPill(text: '급행', color: Colors.red),
              if (train.isLastTrain) _StatusPill(text: '막차', color: Colors.red),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubwayLineBadge extends StatelessWidget {
  const _SubwayLineBadge({required this.line, required this.color});

  final String line;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        line.isEmpty ? '-' : line,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _UniversityFeaturePanel extends StatefulWidget {
  const _UniversityFeaturePanel({required this.module});

  final _HomeModule module;

  @override
  State<_UniversityFeaturePanel> createState() =>
      _UniversityFeaturePanelState();
}

class _UniversityFeaturePanelState extends State<_UniversityFeaturePanel> {
  final AcademyInfoApi _academyInfoApi = AcademyInfoApi();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _directorySearchController =
      TextEditingController();
  final TextEditingController _academyInfoSearchController =
      TextEditingController();
  late Future<AcademyInfoBasicDataset> _academyInfoFuture;
  final Map<String, int> _academyInfoDetailVisibleCounts = {};

  _UniversityDataView _activeDataView = _UniversityDataView.directory;
  String _activeCategory = '전체';
  String _activeArea = '전체';
  String _activeAcademyInfoCategory = '전체';
  int _directoryVisibleCount = 80;

  List<UniversityMajorStat> get _detailStats => kessUniversityMajorStats
      .where((stat) => stat.isDetail)
      .toList(growable: false);

  List<String> get _categories {
    return [
      '전체',
      ...{for (final stat in _detailStats) stat.largeCategory},
    ];
  }

  List<String> get _areas {
    return [
      '전체',
      ...{
        for (final item in careerNetUniversityMajorOfferings) item.areaName,
      }.where((area) => area.isNotEmpty),
    ];
  }

  List<String> get _academyInfoCategories {
    return [
      '전체',
      ...{for (final item in academyInfoBasicOperations) item.group},
    ];
  }

  @override
  void initState() {
    super.initState();
    _academyInfoFuture = _academyInfoApi.loadBasicInformation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _directorySearchController.dispose();
    _academyInfoSearchController.dispose();
    super.dispose();
  }

  void _refreshAcademyInfo() {
    setState(() {
      _academyInfoFuture = _academyInfoApi.loadBasicInformation();
      _academyInfoDetailVisibleCounts.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = switch (_activeDataView) {
      _UniversityDataView.directory => _directoryChildren(context),
      _UniversityDataView.academyInfo => _academyInfoChildren(context),
      _UniversityDataView.kessStats => _kessStatsChildren(context),
    };
    final sourceLabel = switch (_activeDataView) {
      _UniversityDataView.directory => 'CareerNet',
      _UniversityDataView.academyInfo => 'data.go.kr',
      _UniversityDataView.kessStats => 'KESS 2020',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.school_outlined, color: widget.module.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '대학 정보',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusPill(text: sourceLabel, color: widget.module.accent),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('대학별 학과'),
                  selected: _activeDataView == _UniversityDataView.directory,
                  onSelected: (_) {
                    setState(
                      () => _activeDataView = _UniversityDataView.directory,
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('대학알리미 기본정보'),
                  selected: _activeDataView == _UniversityDataView.academyInfo,
                  onSelected: (_) {
                    setState(
                      () => _activeDataView = _UniversityDataView.academyInfo,
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('학과계열 통계'),
                  selected: _activeDataView == _UniversityDataView.kessStats,
                  onSelected: (_) {
                    setState(
                      () => _activeDataView = _UniversityDataView.kessStats,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  List<Widget> _directoryChildren(BuildContext context) {
    final visibleOfferings = careerNetUniversityMajorOfferings
        .where((item) => item.matches(_directorySearchController.text))
        .where((item) => _activeArea == '전체' || item.areaName == _activeArea)
        .toList(growable: false);
    final visibleCount = math.min(
      _directoryVisibleCount,
      visibleOfferings.length,
    );

    return [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _UniversitySummaryTile(
            icon: Icons.account_balance_outlined,
            label: '대학/캠퍼스',
            value: '$careerNetUniversityMajorSchoolCount개',
            color: widget.module.accent,
          ),
          _UniversitySummaryTile(
            icon: Icons.school_outlined,
            label: '개설학과',
            value: '$careerNetUniversityMajorOfferingCount개',
            color: KangColors.royalPurple,
          ),
          _UniversitySummaryTile(
            icon: Icons.category_outlined,
            label: '표준학과',
            value: '$careerNetUniversityMajorCatalogCount개',
            color: KangColors.mintDeep,
          ),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _directorySearchController,
        onChanged: (_) {
          setState(() => _directoryVisibleCount = 80);
        },
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.manage_search_rounded),
          labelText: '대학/학과 검색',
          hintText: '예: 고려대학교, 법학과, 서울특별시',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final area in _areas)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(area),
                  selected: _activeArea == area,
                  onSelected: (_) {
                    setState(() {
                      _activeArea = area;
                      _directoryVisibleCount = 80;
                    });
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _UniversitySourceNote(
        color: widget.module.accent,
        title:
            '$careerNetUniversityMajorSourceTitle · '
            '표준학과 $careerNetUniversityMajorCatalogCount개',
        description:
            '커리어넷 대학교 학과정보의 개설대학 데이터를 기준으로 '
            '대학명, 캠퍼스, 실제 학과명을 정리했습니다.',
      ),
      const SizedBox(height: 14),
      _DriveRowsHeader(
        count: visibleOfferings.length,
        loading: false,
        color: widget.module.accent,
        title: '대학별 학과 리스트',
      ),
      const SizedBox(height: 8),
      if (visibleOfferings.isEmpty)
        const _CalendarMessage(
          icon: Icons.school_outlined,
          text: '일치하는 대학별 학과 정보가 없습니다.',
          color: KangColors.slate,
        )
      else ...[
        for (final item in visibleOfferings.take(visibleCount))
          _UniversityOfferingTile(item: item, color: widget.module.accent),
        if (visibleCount < visibleOfferings.length) ...[
          const SizedBox(height: 4),
          OutlinedButton.icon(
            icon: const Icon(Icons.expand_more_rounded),
            label: Text('더 보기 (${visibleOfferings.length - visibleCount}개 남음)'),
            onPressed: () {
              setState(() => _directoryVisibleCount += 80);
            },
          ),
        ],
      ],
    ];
  }

  List<Widget> _academyInfoChildren(BuildContext context) {
    final query = _academyInfoSearchController.text;
    final showAll = _activeAcademyInfoCategory == '전체';
    final showCodeCategories = showAll || _activeAcademyInfoCategory == '코드표';
    final visibleCodeCategories = showCodeCategories
        ? academyInfoCodeCategories
              .where((item) => item.matches(query))
              .toList(growable: false)
        : const <AcademyInfoCodeCategory>[];
    final visibleOperations = academyInfoBasicOperations
        .where((item) => item.matches(query))
        .where((item) => showAll || item.group == _activeAcademyInfoCategory)
        .toList(growable: false);

    return [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _UniversitySummaryTile(
            icon: Icons.api_outlined,
            label: '상세기능',
            value: '$academyInfoBasicOperationCount개',
            color: widget.module.accent,
          ),
          _UniversitySummaryTile(
            icon: Icons.view_list_outlined,
            label: '코드 분류',
            value: '$academyInfoBasicCodeCategoryCount개',
            color: KangColors.royalPurple,
          ),
          _UniversitySummaryTile(
            icon: Icons.data_object_rounded,
            label: '포맷',
            value: academyInfoBasicFormat,
            color: KangColors.mintDeep,
          ),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _academyInfoSearchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.manage_search_rounded),
          labelText: '기본정보 검색',
          hintText: '예: 지역, 설립유형, 대학 코드, 재적학생',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final category in _academyInfoCategories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(category),
                  selected: _activeAcademyInfoCategory == category,
                  onSelected: (_) {
                    setState(() => _activeAcademyInfoCategory = category);
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _UniversitySourceNote(
        color: widget.module.accent,
        title:
            '$academyInfoBasicSourceTitle · '
            '$academyInfoBasicProvider',
        description:
            '서버에서 인증키를 사용해 OpenAPI를 호출하고, '
            '대학 검색, 코드표, 연도·지표 조회 결과를 API별로 분리합니다.',
      ),
      const SizedBox(height: 14),
      _AcademyInfoLiveDataPanel(
        future: _academyInfoFuture,
        query: query,
        activeCategory: _activeAcademyInfoCategory,
        color: widget.module.accent,
        onRefresh: _refreshAcademyInfo,
      ),
      if (showCodeCategories) ...[
        const SizedBox(height: 14),
        _DriveRowsHeader(
          count: visibleCodeCategories.length,
          loading: false,
          color: widget.module.accent,
          title: '코드표 분류',
        ),
        const SizedBox(height: 8),
        if (visibleCodeCategories.isEmpty)
          const _CalendarMessage(
            icon: Icons.view_list_outlined,
            text: '일치하는 기본정보 코드표가 없습니다.',
            color: KangColors.slate,
          )
        else
          for (final category in visibleCodeCategories)
            _AcademyInfoCodeCategoryTile(
              category: category,
              color: widget.module.accent,
            ),
      ],
      const SizedBox(height: 14),
      _DriveRowsHeader(
        count: visibleOperations.length,
        loading: false,
        color: widget.module.accent,
        title: 'OpenAPI 상세기능',
      ),
      const SizedBox(height: 8),
      if (visibleOperations.isEmpty)
        const _CalendarMessage(
          icon: Icons.api_outlined,
          text: '일치하는 기본정보 상세기능이 없습니다.',
          color: KangColors.slate,
        )
      else
        FutureBuilder<AcademyInfoBasicDataset>(
          future: _academyInfoFuture,
          builder: (context, snapshot) {
            final liveByEndpoint = <String, AcademyInfoOperationResult>{
              for (final item in snapshot.data?.operations ?? const [])
                item.endpoint: item,
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (snapshot.connectionState != ConnectionState.done) ...[
                  const _CalendarMessage(
                    icon: Icons.cloud_sync_outlined,
                    text: '대학알리미 API 데이터를 불러오고 있습니다.',
                    color: KangColors.slate,
                  ),
                  const SizedBox(height: 8),
                ] else if (snapshot.hasError) ...[
                  _AcademyInfoApiNotice(
                    color: Colors.red.shade600,
                    icon: Icons.error_outline_rounded,
                    title: '대학알리미 API 데이터를 불러오지 못했습니다.',
                    message: snapshot.error?.toString() ?? '알 수 없는 오류가 발생했습니다.',
                  ),
                  const SizedBox(height: 8),
                ],
                for (final operation in visibleOperations)
                  _AcademyInfoOperationTile(
                    operation: operation,
                    result: liveByEndpoint[operation.endpoint],
                    visibleCount:
                        _academyInfoDetailVisibleCounts[operation.endpoint] ??
                        _academyInfoInitialVisibleCount(
                          liveByEndpoint[operation.endpoint],
                        ),
                    color: widget.module.accent,
                    onShowMore: liveByEndpoint[operation.endpoint] == null
                        ? null
                        : () {
                            final result = liveByEndpoint[operation.endpoint]!;
                            setState(() {
                              _academyInfoDetailVisibleCounts[operation
                                      .endpoint] =
                                  (_academyInfoDetailVisibleCounts[operation
                                          .endpoint] ??
                                      _academyInfoInitialVisibleCount(result)) +
                                  20;
                            });
                          },
                  ),
              ],
            );
          },
        ),
    ];
  }

  List<Widget> _kessStatsChildren(BuildContext context) {
    final totalStat = kessUniversityMajorStats.first;
    final visibleStats = _detailStats
        .where((stat) => stat.matches(_searchController.text))
        .where(
          (stat) =>
              _activeCategory == '전체' || stat.largeCategory == _activeCategory,
        )
        .toList(growable: false);

    return [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _UniversitySummaryTile(
            icon: Icons.category_outlined,
            label: '학과 분류',
            value: '${_detailStats.length}개',
            color: widget.module.accent,
          ),
          _UniversitySummaryTile(
            icon: Icons.groups_2_outlined,
            label: '지원자',
            value: '${_formatKessNumber(totalStat.applicantsTotal)}명',
            color: KangColors.royalPurple,
          ),
          _UniversitySummaryTile(
            icon: Icons.how_to_reg_outlined,
            label: '입학자',
            value: '${_formatKessNumber(totalStat.entrantsTotal)}명',
            color: KangColors.mintDeep,
          ),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.manage_search_rounded),
          labelText: '학과 검색',
          hintText: '대분류, 중분류, 소분류',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final category in _categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(category),
                  selected: _activeCategory == category,
                  onSelected: (_) {
                    setState(() => _activeCategory = category);
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _UniversitySourceNote(
        color: widget.module.accent,
        title:
            '$kessUniversityMajorSourceTitle · '
            '$kessUniversityMajorSurveyYear년',
        description:
            'KESS 대학과정 학과계열 통계입니다. '
            '단위: $kessUniversityMajorUnit',
      ),
      const SizedBox(height: 14),
      _DriveRowsHeader(
        count: visibleStats.length,
        loading: false,
        color: widget.module.accent,
        title: '학과계열 리스트',
      ),
      const SizedBox(height: 8),
      if (visibleStats.isEmpty)
        const _CalendarMessage(
          icon: Icons.school_outlined,
          text: '일치하는 대학 학과계열 정보가 없습니다.',
          color: KangColors.slate,
        )
      else
        for (final stat in visibleStats)
          _UniversityMajorTile(stat: stat, color: widget.module.accent),
    ];
  }
}

enum _UniversityDataView { directory, academyInfo, kessStats }

int _academyInfoInitialVisibleCount(AcademyInfoOperationResult? operation) {
  if (operation?.isUniversityList ?? false) {
    return 10;
  }
  return 18;
}

class _AcademyInfoLiveDataPanel extends StatefulWidget {
  const _AcademyInfoLiveDataPanel({
    required this.future,
    required this.query,
    required this.activeCategory,
    required this.color,
    required this.onRefresh,
  });

  final Future<AcademyInfoBasicDataset> future;
  final String query;
  final String activeCategory;
  final Color color;
  final VoidCallback onRefresh;

  @override
  State<_AcademyInfoLiveDataPanel> createState() =>
      _AcademyInfoLiveDataPanelState();
}

class _AcademyInfoLiveDataPanelState extends State<_AcademyInfoLiveDataPanel> {
  final Map<String, int> _visibleCounts = {};

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AcademyInfoBasicDataset>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _AcademyInfoLiveShell(
            color: widget.color,
            summary: const [
              _AcademyInfoSummaryData(Icons.api_outlined, '실시간 호출', '확인 중'),
              _AcademyInfoSummaryData(Icons.table_rows_outlined, '수집 데이터', '-'),
              _AcademyInfoSummaryData(Icons.cloud_sync_outlined, '상태', '연결 중'),
            ],
            child: const _CalendarMessage(
              icon: Icons.cloud_sync_outlined,
              text: '대학알리미 OpenAPI 데이터를 불러오고 있습니다.',
              color: KangColors.slate,
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _AcademyInfoLiveShell(
            color: widget.color,
            onRefresh: widget.onRefresh,
            summary: const [
              _AcademyInfoSummaryData(Icons.api_outlined, '실시간 호출', '실패'),
              _AcademyInfoSummaryData(
                Icons.table_rows_outlined,
                '수집 데이터',
                '0개',
              ),
              _AcademyInfoSummaryData(Icons.error_outline_rounded, '상태', '오류'),
            ],
            child: _AcademyInfoApiNotice(
              color: Colors.red.shade600,
              icon: Icons.error_outline_rounded,
              title: '대학알리미 API 데이터를 불러오지 못했습니다.',
              message: snapshot.error?.toString() ?? '알 수 없는 오류가 발생했습니다.',
            ),
          );
        }

        final dataset = snapshot.data!;
        final operations = dataset.operations
            .where((item) => item.matches(widget.query))
            .where(
              (item) =>
                  widget.activeCategory == '전체' ||
                  item.group == widget.activeCategory,
            )
            .toList(growable: false);
        final statusLabel = switch (dataset.status) {
          'ok' => '정상',
          'partial' => '부분 성공',
          _ => '오류',
        };

        return _AcademyInfoLiveShell(
          color: widget.color,
          onRefresh: widget.onRefresh,
          summary: [
            _AcademyInfoSummaryData(
              Icons.api_outlined,
              '실시간 호출',
              '${dataset.summary.successCount}/${dataset.summary.operationCount}개',
            ),
            _AcademyInfoSummaryData(
              Icons.table_rows_outlined,
              '수집 데이터',
              '${_formatKessNumber(dataset.summary.totalRows)}개',
            ),
            _AcademyInfoSummaryData(
              Icons.cloud_done_outlined,
              '상태',
              statusLabel,
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (dataset.hasErrors) ...[
                _AcademyInfoApiNotice(
                  color: Colors.orange.shade700,
                  icon: Icons.key_off_outlined,
                  title: '일부 API 호출이 성공하지 않았습니다.',
                  message:
                      '현재 응답에 오류가 포함되어 있습니다. '
                      '각 모듈의 결과 메시지에서 원인을 확인할 수 있습니다.',
                ),
                const SizedBox(height: 10),
              ],
              _DriveRowsHeader(
                count: operations.length,
                loading: false,
                color: widget.color,
                title: 'API별 수집 데이터',
              ),
              const SizedBox(height: 8),
              if (operations.isEmpty)
                const _CalendarMessage(
                  icon: Icons.api_outlined,
                  text: '일치하는 API 데이터 모듈이 없습니다.',
                  color: KangColors.slate,
                )
              else
                for (final operation in operations)
                  _AcademyInfoLiveOperationTile(
                    operation: operation,
                    visibleCount:
                        _visibleCounts[operation.endpoint] ??
                        _initialVisibleCount(operation),
                    color: widget.color,
                    onShowMore: () {
                      setState(() {
                        _visibleCounts[operation.endpoint] =
                            (_visibleCounts[operation.endpoint] ??
                                _initialVisibleCount(operation)) +
                            20;
                      });
                    },
                  ),
            ],
          ),
        );
      },
    );
  }

  int _initialVisibleCount(AcademyInfoOperationResult operation) {
    return _academyInfoInitialVisibleCount(operation);
  }
}

class _AcademyInfoSummaryData {
  const _AcademyInfoSummaryData(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _AcademyInfoLiveShell extends StatelessWidget {
  const _AcademyInfoLiveShell({
    required this.color,
    required this.summary,
    required this.child,
    this.onRefresh,
  });

  final Color color;
  final List<_AcademyInfoSummaryData> summary;
  final Widget child;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in summary)
                    _UniversitySummaryTile(
                      icon: item.icon,
                      label: item.label,
                      value: item.value,
                      color: color,
                    ),
                ],
              ),
            ),
            if (onRefresh != null) ...[
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: '대학알리미 API 다시 불러오기',
                icon: const Icon(Icons.refresh_rounded),
                color: color,
                onPressed: onRefresh,
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _AcademyInfoApiNotice extends StatelessWidget {
  const _AcademyInfoApiNotice({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: KangColors.slate,
                      height: 1.35,
                    ),
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

class _AcademyInfoLiveOperationTile extends StatelessWidget {
  const _AcademyInfoLiveOperationTile({
    required this.operation,
    required this.visibleCount,
    required this.color,
    required this.onShowMore,
  });

  final AcademyInfoOperationResult operation;
  final int visibleCount;
  final Color color;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) {
    final statusColor = operation.isOk ? color : Colors.red.shade600;
    final rows = operation.rows.take(visibleCount).toList(growable: false);
    final total = operation.totalCount == 0
        ? operation.rowCount
        : operation.totalCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  operation.isOk
                      ? Icons.cloud_done_outlined
                      : Icons.error_outline_rounded,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      operation.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      operation.endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(text: operation.group, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            operation.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: KangColors.slate,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _UniversityMetric(
                label: '결과',
                value: operation.isOk ? '정상' : '오류',
              ),
              _UniversityMetric(label: '응답코드', value: operation.resultCode),
              _UniversityMetric(
                label: '건수',
                value: '${_formatKessNumber(total)}개',
              ),
              if (operation.requestParams.isNotEmpty)
                _UniversityMetric(
                  label: '요청값',
                  value: operation.requestParams.entries
                      .map((entry) => '${entry.key}=${entry.value}')
                      .join(', '),
                ),
            ],
          ),
          if (operation.resultMsg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              operation.resultMsg,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: operation.isOk ? KangColors.slate : Colors.red.shade700,
                fontWeight: operation.isOk ? FontWeight.w500 : FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const _CalendarMessage(
              icon: Icons.table_rows_outlined,
              text: '표시할 응답 데이터가 없습니다.',
              color: KangColors.slate,
            )
          else ...[
            for (final row in rows)
              _AcademyInfoDataRowTile(operation: operation, row: row),
            if (visibleCount < operation.rows.length) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(
                  '더 보기 (${operation.rows.length - visibleCount}개 남음)',
                ),
                onPressed: onShowMore,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AcademyInfoDataRowTile extends StatelessWidget {
  const _AcademyInfoDataRowTile({required this.operation, required this.row});

  final AcademyInfoOperationResult operation;
  final Map<String, String> row;

  @override
  Widget build(BuildContext context) {
    if (operation.isUniversityList) {
      return _AcademyInfoUniversityResultRow(row: row);
    }
    if (operation.isYearList) {
      return _AcademyInfoCompactResultRow(
        title: row['yearVal'] ?? '-',
        subtitle: '연도',
        fields: row,
      );
    }
    return _AcademyInfoCompactResultRow(
      title: row['cdnm'] ?? (row.values.isEmpty ? '-' : row.values.first),
      subtitle: row['cdid'] == null ? operation.endpoint : '코드 ${row['cdid']}',
      fields: row,
    );
  }
}

class _AcademyInfoUniversityResultRow extends StatelessWidget {
  const _AcademyInfoUniversityResultRow({required this.row});

  final Map<String, String> row;

  @override
  Widget build(BuildContext context) {
    final title = row['schlKrnNm'] ?? row['schlFullNm'] ?? '-';
    final details = [
      row['schlFullNm'],
      row['clgcpDivNm'],
      row['schlDivNm'],
      row['schlKndNm'],
      row['estbDivNm'],
      row['znNm'],
    ].where((item) => item != null && item.isNotEmpty).cast<String>().toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.account_balance_outlined,
            color: KangColors.royalPurple,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: KangColors.slate,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if ((row['schlId'] ?? '').isNotEmpty) ...[
            const SizedBox(width: 8),
            _StatusPill(text: row['schlId']!, color: KangColors.royalPurple),
          ],
        ],
      ),
    );
  }
}

class _AcademyInfoCompactResultRow extends StatelessWidget {
  const _AcademyInfoCompactResultRow({
    required this.title,
    required this.subtitle,
    required this.fields,
  });

  final String title;
  final String subtitle;
  final Map<String, String> fields;

  @override
  Widget build(BuildContext context) {
    final detail = fields.entries
        .map((entry) => '${_academyInfoFieldLabel(entry.key)} ${entry.value}')
        .join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.label_outline_rounded,
            color: KangColors.royalPurple,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KangColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail.isEmpty ? subtitle : detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: KangColors.slate,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcademyInfoCodeCategoryTile extends StatelessWidget {
  const _AcademyInfoCodeCategoryTile({
    required this.category,
    required this.color,
  });

  final AcademyInfoCodeCategory category;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final visibleValues = category.values.take(18).toList(growable: false);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.view_list_outlined, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: KangColors.slate,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                text: category.sampleOnly
                    ? '예시 ${visibleValues.length}/${category.totalCount}'
                    : '${category.totalCount}개',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in visibleValues)
                _AcademyInfoCodeChip(value: value, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            category.endpoint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _AcademyInfoCodeChip extends StatelessWidget {
  const _AcademyInfoCodeChip({required this.value, required this.color});

  final AcademyInfoCodeValue value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = value.remark.isEmpty
        ? '${value.code} · ${value.name}'
        : '${value.code} · ${value.name} · ${value.remark}';

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: KangColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
    );
  }
}

class _AcademyInfoOperationTile extends StatelessWidget {
  const _AcademyInfoOperationTile({
    required this.operation,
    required this.color,
    this.result,
    this.visibleCount = 0,
    this.onShowMore,
  });

  final AcademyInfoBasicOperation operation;
  final AcademyInfoOperationResult? result;
  final int visibleCount;
  final Color color;
  final VoidCallback? onShowMore;

  @override
  Widget build(BuildContext context) {
    final liveResult = result;
    final statusColor = liveResult == null
        ? color
        : liveResult.isOk
        ? color
        : Colors.red.shade600;
    final rows = liveResult == null
        ? const <Map<String, String>>[]
        : liveResult.rows.take(visibleCount).toList(growable: false);
    final total = liveResult == null
        ? 0
        : liveResult.totalCount == 0
        ? liveResult.rowCount
        : liveResult.totalCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  liveResult == null
                      ? Icons.api_outlined
                      : liveResult.isOk
                      ? Icons.cloud_done_outlined
                      : Icons.error_outline_rounded,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      operation.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      operation.endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(text: operation.group, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            operation.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: KangColors.slate,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AcademyInfoFieldGroup(
                label: '필수',
                values: operation.requiredParams,
              ),
              if (operation.optionalParams.isNotEmpty)
                _AcademyInfoFieldGroup(
                  label: '선택',
                  values: operation.optionalParams,
                ),
              _AcademyInfoFieldGroup(
                label: '응답',
                values: operation.responseFields,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (liveResult == null)
            const _CalendarMessage(
              icon: Icons.cloud_sync_outlined,
              text: '이 API의 호출 데이터를 불러오고 있습니다.',
              color: KangColors.slate,
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _UniversityMetric(
                  label: '결과',
                  value: liveResult.isOk ? '정상' : '오류',
                ),
                _UniversityMetric(label: '응답코드', value: liveResult.resultCode),
                _UniversityMetric(
                  label: '건수',
                  value: '${_formatKessNumber(total)}개',
                ),
                if (liveResult.requestParams.isNotEmpty)
                  _UniversityMetric(
                    label: '요청값',
                    value: liveResult.requestParams.entries
                        .map((entry) => '${entry.key}=${entry.value}')
                        .join(', '),
                  ),
              ],
            ),
            if (liveResult.resultMsg.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                liveResult.resultMsg,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: liveResult.isOk
                      ? KangColors.slate
                      : Colors.red.shade700,
                  fontWeight: liveResult.isOk
                      ? FontWeight.w500
                      : FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const _CalendarMessage(
                icon: Icons.table_rows_outlined,
                text: '표시할 응답 데이터가 없습니다.',
                color: KangColors.slate,
              )
            else ...[
              for (final row in rows)
                _AcademyInfoDataRowTile(operation: liveResult, row: row),
              if (visibleCount < liveResult.rows.length &&
                  onShowMore != null) ...[
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    '더 보기 (${liveResult.rows.length - visibleCount}개 남음)',
                  ),
                  onPressed: onShowMore,
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class _AcademyInfoFieldGroup extends StatelessWidget {
  const _AcademyInfoFieldGroup({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 116, maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
          ),
          const SizedBox(height: 3),
          Text(
            values.join(', '),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KangColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _UniversityOfferingTile extends StatelessWidget {
  const _UniversityOfferingTile({required this.item, required this.color});

  final CareerNetUniversityMajorOffering item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.account_balance_outlined, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.schoolName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        item.areaName,
                        item.campusName,
                        item.schoolType,
                      ].where((value) => value.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(text: item.category, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.majorName,
            style: const TextStyle(
              color: KangColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (item.catalogMajorName.isNotEmpty &&
              item.catalogMajorName != item.majorName) ...[
            const SizedBox(height: 5),
            Text(
              '커리어넷 표준학과: ${item.catalogMajorName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
            ),
          ],
          if (item.schoolUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.schoolUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ],
          if (item.updatedAt.isNotEmpty) ...[
            const SizedBox(height: 8),
            _StatusPill(text: '업데이트 ${item.updatedAt}', color: color),
          ],
        ],
      ),
    );
  }
}

class _UniversitySourceNote extends StatelessWidget {
  const _UniversitySourceNote({
    required this.color,
    required this.title,
    required this.description,
  });

  final Color color;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.dataset_linked_outlined, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: KangColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: KangColors.slate,
                      height: 1.35,
                    ),
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

class _UniversitySummaryTile extends StatelessWidget {
  const _UniversitySummaryTile({
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
    return Container(
      width: 164,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UniversityMajorTile extends StatelessWidget {
  const _UniversityMajorTile({required this.stat, required this.color});

  final UniversityMajorStat stat;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.school_outlined, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.smallCategory,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stat.largeCategory} · ${stat.middleCategory}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                text: '${stat.fillRate.toStringAsFixed(1)}%',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _UniversityMetric(
                label: '입학정원',
                value: '${_formatKessNumber(stat.admissionQuotaRegular)}명',
              ),
              _UniversityMetric(
                label: '모집인원',
                value: '${_formatKessNumber(stat.recruitmentTotal)}명',
              ),
              _UniversityMetric(
                label: '지원자',
                value: '${_formatKessNumber(stat.applicantsTotal)}명',
              ),
              _UniversityMetric(
                label: '입학자',
                value: '${_formatKessNumber(stat.entrantsTotal)}명',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UniversityMetric extends StatelessWidget {
  const _UniversityMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KangColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatKessNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i += 1) {
    final remaining = text.length - i;
    buffer.write(text[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

String _formatUsdCompact(int value) {
  final absolute = value.abs();
  if (absolute >= 1000000000000) {
    return '\$${_trimDecimal(value / 1000000000000, digits: 2)}T';
  }
  if (absolute >= 1000000000) {
    return '\$${_trimDecimal(value / 1000000000, digits: 2)}B';
  }
  if (absolute >= 1000000) {
    return '\$${_trimDecimal(value / 1000000, digits: 2)}M';
  }
  return '\$${_formatKessNumber(value)}';
}

String _formatUsdPrice(double? value) {
  if (value == null) {
    return '-';
  }
  return '\$${_trimDecimal(value, digits: 2)}';
}

String _formatRatePercent(double? value) {
  if (value == null) {
    return '-';
  }
  return '${_trimDecimal(value, digits: 2)}%';
}

String _formatSpreadPercent(double? value) {
  if (value == null) {
    return '-';
  }
  return '${_trimDecimal(value, digits: 2)}%p';
}

String _formatBasisPointChange(double? value) {
  if (value == null) {
    return '-';
  }
  final basisPoints = value * 100;
  final sign = basisPoints > 0 ? '+' : '';
  return '$sign${_trimDecimal(basisPoints, digits: 1)}bp';
}

String _formatFxRate(double? value) {
  if (value == null || value == 0) {
    return '-';
  }
  final digits = value >= 100
      ? 2
      : value >= 10
      ? 3
      : 4;
  return _trimDecimal(value, digits: digits);
}

String _formatFxChange(double? value, double? rate) {
  if (value == null) {
    return '-';
  }
  final absoluteRate = (rate ?? value).abs();
  final digits = absoluteRate >= 100
      ? 2
      : absoluteRate >= 10
      ? 3
      : 4;
  final sign = value > 0 ? '+' : '';
  return '$sign${_trimDecimal(value, digits: digits)}';
}

String _formatMarketQuotePrice(double? value) {
  if (value == null) {
    return '-';
  }
  return _trimDecimal(value, digits: value >= 1000 ? 2 : 3);
}

String _formatSignedNumber(double? value) {
  if (value == null) {
    return '-';
  }
  final sign = value > 0 ? '+' : '';
  return '$sign${_trimDecimal(value, digits: 2)}';
}

String _formatSignedPercent(double? value) {
  if (value == null) {
    return '-';
  }
  final sign = value > 0 ? '+' : '';
  return '$sign${_trimDecimal(value, digits: 2)}%';
}

String _formatSubwayEta(int? seconds) {
  if (seconds == null) {
    return '도착 확인';
  }
  if (seconds <= 0) {
    return '곧 도착';
  }
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  if (minutes <= 0) {
    return '$remainder초';
  }
  return '$minutes분 $remainder초';
}

List<MapEntry<String, List<SubwayArrival>>> _groupSubwayArrivalsByDirection(
  List<SubwayArrival> arrivals,
) {
  final groups = <String, List<SubwayArrival>>{
    '상행': <SubwayArrival>[],
    '하행': <SubwayArrival>[],
  };
  for (final arrival in arrivals) {
    groups[_subwayDirectionKey(arrival)]!.add(arrival);
  }
  return groups.entries.toList(growable: false);
}

String _subwayDirectionKey(SubwayArrival arrival) {
  final haystack = [
    arrival.direction,
    arrival.trainLine,
    arrival.arrivalMessage,
  ].join(' ');
  if (haystack.contains('하행') ||
      haystack.contains('하선') ||
      haystack.contains('내선')) {
    return '하행';
  }
  return '상행';
}

bool _isSubwayDirection(SubwayArrival arrival, String direction) {
  return _subwayDirectionKey(arrival) == direction;
}

String _formatSubwayDirectionTitle(String direction) {
  if (direction == '상행' || direction == '하행') {
    return '$direction방향';
  }
  return direction.isEmpty ? '방향 확인' : '$direction 방면';
}

String _formatSubwayArrivalEta(SubwayArrival arrival) {
  final seconds = arrival.etaSeconds;
  if (seconds != null && seconds > 0) {
    final minutes = seconds ~/ 60;
    if (minutes <= 0) {
      return '$seconds초';
    }
    return '$minutes분';
  }
  if (arrival.status == '도착' || arrival.arrivalMessage.contains('도착')) {
    return '도착';
  }
  if (arrival.arrivalMessage.contains('진입')) {
    return '진입';
  }
  return '확인중';
}

Color _subwayArrivalEtaColor(SubwayArrival arrival, Color fallback) {
  final seconds = arrival.etaSeconds;
  if (seconds == null) {
    return fallback;
  }
  if (seconds <= 120) {
    return Colors.red.shade600;
  }
  return fallback;
}

String _formatSubwayTime(String value) {
  if (value.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

Color _colorFromHex(String value, Color fallback) {
  final normalized = value.trim().replaceFirst('#', '');
  if (normalized.length != 6) {
    return fallback;
  }
  final colorValue = int.tryParse(normalized, radix: 16);
  if (colorValue == null) {
    return fallback;
  }
  return Color(0xFF000000 | colorValue);
}

Color _subwayColorForLine(String line, Color fallback) {
  return switch (line) {
    '1호선' => const Color(0xFF0052A4),
    '2호선' => const Color(0xFF00A84D),
    '3호선' => const Color(0xFFEF7C1C),
    '4호선' => const Color(0xFF00A5DE),
    '5호선' => const Color(0xFF996CAC),
    '6호선' => const Color(0xFFCD7C2F),
    '7호선' => const Color(0xFF747F00),
    '8호선' => const Color(0xFFE6186C),
    '9호선' => const Color(0xFFBDB092),
    '신분당선' => const Color(0xFFD4003B),
    '공항철도' => const Color(0xFF0090D2),
    '경의중앙선' => const Color(0xFF77C4A3),
    '수인분당선' => const Color(0xFFF5A200),
    _ => fallback,
  };
}

String _trimDecimal(num value, {int digits = 2}) {
  var text = value.toStringAsFixed(digits);
  if (!text.contains('.')) {
    return text;
  }
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

String _formatMarketCapDate(String value) {
  if (value.isEmpty) {
    return '-';
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }
  final local = parsed.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String _formatKeepDate(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) {
    return '-';
  }
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}.$month.$day $hour:$minute';
}

String _academyInfoFieldLabel(String field) {
  return switch (field) {
    'cdid' => '코드',
    'cdnm' => '값',
    'rmk' => '단위',
    'yearVal' => '연도',
    'svyYr' => '공시년도',
    'schlId' => '학교ID',
    'schlKrnNm' => '대학명',
    'schlFullNm' => '전체명',
    'clgcpDivCd' => '본분교코드',
    'clgcpDivNm' => '본분교',
    'schlDivCd' => '종류코드',
    'schlDivNm' => '학교종류',
    'schlKndCd' => '유형코드',
    'schlKndNm' => '학교유형',
    'estbDivCd' => '설립코드',
    'estbDivNm' => '설립',
    'znCd' => '지역코드',
    'znNm' => '지역',
    _ => field,
  };
}

class _KeepFeaturePanel extends StatefulWidget {
  const _KeepFeaturePanel({required this.module});

  final _HomeModule module;

  @override
  State<_KeepFeaturePanel> createState() => _KeepFeaturePanelState();
}

class _KeepFeaturePanelState extends State<_KeepFeaturePanel> {
  final GoogleKeepService _keepService = GoogleKeepService();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = false;
  GoogleKeepNotesDataset? _dataset = const GoogleKeepNotesDataset(
    notes: [],
    apiUnavailable: true,
  );
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _connect() {
    return _loadNotes(interactive: true);
  }

  Future<void> _loadNotes({bool interactive = false}) async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dataset = await _keepService.loadNotes(interactive: interactive);
      if (!mounted) {
        return;
      }
      setState(() => _dataset = dataset);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (!interactive && _isMissingKeepToken(error)) {
        setState(() => _error = null);
        return;
      }
      setState(() => _error = _keepErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataset = _dataset;
    final apiUnavailable = dataset?.apiUnavailable ?? false;
    final connected = dataset != null && _error == null && !apiUnavailable;
    final blocked = _error != null;
    final openKeepMode = apiUnavailable;
    final filteredNotes = (dataset?.notes ?? const <GoogleKeepNote>[])
        .where((note) => note.matches(_searchController.text))
        .toList(growable: false);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.sticky_note_2_outlined, color: widget.module.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Google Keep',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusPill(
                  text: connected
                      ? '연동됨'
                      : apiUnavailable
                      ? '웹에서 확인'
                      : blocked
                      ? '연동 제한'
                      : '자동 확인',
                  color: blocked
                      ? const Color(0xFFBA1A1A)
                      : widget.module.accent,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (apiUnavailable)
              _KeepApiUnavailablePanel(color: widget.module.accent)
            else ...[
              _KeepStatStrip(dataset: dataset, color: widget.module.accent),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: '검색어 지우기',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  labelText: 'Keep 메모 검색',
                  hintText: '제목, 본문, 체크리스트 항목 검색',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _KeepPrimaryAction(
              loading: _loading,
              openKeepMode: openKeepMode,
              connected: connected,
              onRefresh: _connect,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _CalendarMessage(
                icon: Icons.error_outline,
                text: _error!,
                color: const Color(0xFFBA1A1A),
              ),
            ],
            if (connected) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '최근 메모',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _StatusPill(
                    text: '${filteredNotes.length}개 표시',
                    color: widget.module.accent,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (filteredNotes.isEmpty)
                const _CalendarMessage(
                  icon: Icons.note_alt_outlined,
                  text: '표시할 Google Keep 메모가 없습니다.',
                  color: KangColors.slate,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 760;
                    final spacing = compact ? 10.0 : 12.0;
                    final cardWidth = compact
                        ? constraints.maxWidth
                        : (constraints.maxWidth - spacing) / 2;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final note in filteredNotes.take(24))
                          SizedBox(
                            width: cardWidth,
                            child: _KeepNoteCard(
                              note: note,
                              color: widget.module.accent,
                              onTap: () => _showKeepNoteDetail(note),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showKeepNoteDetail(GoogleKeepNote note) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final viewport = MediaQuery.sizeOf(dialogContext);
        final compact = viewport.width < 640;
        return Dialog(
          alignment: compact ? Alignment.bottomCenter : Alignment.center,
          insetPadding: compact
              ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 12 : 8),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact ? viewport.width - 16 : 760,
              maxHeight: compact
                  ? viewport.height * 0.82
                  : viewport.height - 48,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: compact
                      ? const EdgeInsets.fromLTRB(16, 12, 4, 12)
                      : const EdgeInsets.fromLTRB(20, 16, 8, 16),
                  decoration: BoxDecoration(
                    color: widget.module.accent.withValues(alpha: 0.12),
                    border: const Border(
                      bottom: BorderSide(color: KangColors.line),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: KangColors.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: compact
                        ? const EdgeInsets.fromLTRB(16, 16, 16, 20)
                        : const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatusPill(
                              text: note.isChecklist ? '체크리스트' : '텍스트',
                              color: widget.module.accent,
                            ),
                            _StatusPill(
                              text: '수정 ${_formatKeepDate(note.updatedAt)}',
                              color: KangColors.slate,
                            ),
                            if (note.attachmentCount > 0)
                              _StatusPill(
                                text: '첨부 ${note.attachmentCount}개',
                                color: KangColors.slate,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (note.isChecklist)
                          _KeepChecklist(
                            note: note,
                            color: widget.module.accent,
                          )
                        else
                          SelectableText(
                            note.text.trim().isEmpty ? '내용이 없습니다.' : note.text,
                            style: const TextStyle(
                              color: KangColors.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.55,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isMissingKeepToken(Object error) {
    return error is FirebaseAuthException &&
        error.code == 'missing-google-access-token';
  }

  String _keepErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'popup-closed-by-user' ||
        'web-context-cancelled' ||
        'cancelled-popup-request' => 'Google Keep 권한 요청이 취소되었습니다.',
        'missing-google-access-token' =>
          'Google 로그인 토큰이 없습니다. Google로 로그인하면 메모 화면에서 자동으로 확인합니다.',
        'keep-scope-denied' => 'Google Keep 웹에서 메모를 확인해 주세요.',
        'account-exists-with-different-credential' =>
          '이 Google 계정은 다른 Firebase 계정에 이미 연결되어 있습니다.',
        _ => error.message ?? 'Google Keep 확인에 실패했습니다.',
      };
    }
    return error
        .toString()
        .replaceFirst('GoogleKeepException: ', '')
        .replaceFirst('Exception: ', '');
  }
}

class _KeepStatStrip extends StatelessWidget {
  const _KeepStatStrip({required this.dataset, required this.color});

  final GoogleKeepNotesDataset? dataset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _KeepStat(
          label: '전체',
          value: dataset == null ? '-' : '${dataset!.notes.length}',
          color: color,
        ),
        _KeepStat(
          label: '텍스트',
          value: dataset == null ? '-' : '${dataset!.textNoteCount}',
          color: color,
        ),
        _KeepStat(
          label: '체크리스트',
          value: dataset == null ? '-' : '${dataset!.checklistCount}',
          color: color,
        ),
      ],
    );
  }
}

class _KeepApiUnavailablePanel extends StatelessWidget {
  const _KeepApiUnavailablePanel({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '아래 버튼을 누르면 현재 Google 로그인 상태 그대로 Google Keep 메모와 체크리스트 화면으로 이동합니다.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: KangColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeepPrimaryAction extends StatelessWidget {
  const _KeepPrimaryAction({
    required this.loading,
    required this.openKeepMode,
    required this.connected,
    required this.onRefresh,
  });

  final bool loading;
  final bool openKeepMode;
  final bool connected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (openKeepMode) {
      return FilledButton.icon(
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('Google Keep 열기'),
        onPressed: () async {
          final opened = await openGoogleKeep();
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Google Keep을 열 수 없습니다.')),
            );
          }
        },
      );
    }

    return FilledButton.icon(
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.sync_rounded),
      label: Text(connected ? '메모 새로고침' : 'Google Keep 다시 확인'),
      onPressed: loading ? null : onRefresh,
    );
  }
}

class _KeepStat extends StatelessWidget {
  const _KeepStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: KangColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeepNoteCard extends StatelessWidget {
  const _KeepNoteCard({
    required this.note,
    required this.color,
    required this.onTap,
  });

  final GoogleKeepNote note;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = note.preview.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          height: 176,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: KangColors.deepPurple.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      note.isChecklist
                          ? Icons.checklist_rounded
                          : Icons.notes_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      note.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Expanded(
                child: Text(
                  preview.isEmpty ? '내용이 없습니다.' : preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: KangColors.slate,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _StatusPill(
                    text: note.isChecklist
                        ? '${note.pendingItemCount}/${note.items.length} 남음'
                        : '텍스트',
                    color: color,
                  ),
                  _StatusPill(
                    text: _formatKeepDate(note.updatedAt),
                    color: KangColors.slate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepChecklist extends StatelessWidget {
  const _KeepChecklist({required this.note, required this.color});

  final GoogleKeepNote note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in note.items)
          Padding(
            padding: EdgeInsets.only(left: item.child ? 24 : 0, bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.checked
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: item.checked ? color : KangColors.slate,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(
                    item.text.trim().isEmpty ? '내용 없음' : item.text,
                    style: TextStyle(
                      color: item.checked ? KangColors.slate : KangColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.42,
                      decoration: item.checked
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DriveFeaturePanel extends StatefulWidget {
  const _DriveFeaturePanel({required this.module});

  final _HomeModule module;

  @override
  State<_DriveFeaturePanel> createState() => _DriveFeaturePanelState();
}

class _DriveFeaturePanelState extends State<_DriveFeaturePanel> {
  final GoogleDriveApi _driveApi = GoogleDriveApi();
  final TextEditingController _searchController = TextEditingController();

  bool _loadingFiles = false;
  bool _loadingRows = false;
  String? _selectedFileId;
  String? _importingSheetKey;
  String? _error;
  String? _message;
  List<GoogleDriveSheetFile> _files = const [];
  List<GoogleDriveTableRowData> _rows = const [];
  final Set<String> _loadingSheetFileIds = {};
  final Set<String> _loadedSheetFileIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFiles();
      _loadRows();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    if (_loadingFiles) {
      return;
    }
    setState(() {
      _loadingFiles = true;
      _error = null;
      _message = null;
    });

    try {
      final files = await _driveApi.listSheetFiles(
        query: _searchController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _files = files;
        _selectedFileId = null;
        _loadingSheetFileIds.clear();
        _loadedSheetFileIds.clear();
        _message = files.isEmpty
            ? 'Google Drive에서 Google Sheet 파일을 찾지 못했습니다.'
            : 'Google Sheet ${files.length}개를 불러왔습니다.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _driveErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loadingFiles = false);
      }
    }
  }

  Future<void> _importSheet(GoogleDriveSheetFile file, String sheetName) async {
    if (_importingSheetKey != null) {
      return;
    }
    final sheetKey = _sheetKey(file, sheetName);
    setState(() {
      _importingSheetKey = sheetKey;
      _error = null;
      _message = null;
    });

    try {
      final result = await _driveApi.importSheet(file, sheetName: sheetName);
      if (!mounted) {
        return;
      }
      setState(() {
        _message =
            '${result.fileName} / ${result.sheetName ?? sheetName}에서 ${result.importedRows}개 행을 가져왔습니다.';
      });
      await _loadRows();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _driveErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _importingSheetKey = null);
      }
    }
  }

  String _sheetKey(GoogleDriveSheetFile file, String sheetName) {
    return '${file.id}::$sheetName';
  }

  Future<void> _toggleFile(GoogleDriveSheetFile file) async {
    final willSelect = _selectedFileId != file.id;
    setState(() {
      _selectedFileId = willSelect ? file.id : null;
      _error = null;
    });

    if (willSelect && !_loadedSheetFileIds.contains(file.id)) {
      await _loadSheetNames(file);
    }
  }

  Future<void> _loadSheetNames(GoogleDriveSheetFile file) async {
    if (_loadingSheetFileIds.contains(file.id)) {
      return;
    }

    setState(() => _loadingSheetFileIds.add(file.id));

    try {
      final sheetNames = await _driveApi.listSheetNames(file);
      if (!mounted) {
        return;
      }
      setState(() {
        _files = [
          for (final item in _files)
            if (item.id == file.id)
              item.copyWith(sheetNames: sheetNames)
            else
              item,
        ];
        _loadedSheetFileIds.add(file.id);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _driveErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loadingSheetFileIds.remove(file.id));
      }
    }
  }

  Future<void> _loadRows() async {
    if (_loadingRows) {
      return;
    }
    setState(() {
      _loadingRows = true;
      _error = null;
    });

    try {
      final rows = await _driveApi.listRows(search: _searchController.text);
      if (!mounted) {
        return;
      }
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _driveErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loadingRows = false);
      }
    }
  }

  Future<void> _openRowsViewer() async {
    if (_loadingRows) {
      return;
    }

    List<GoogleDriveTableRowData> rows = const [];
    var loaded = false;
    setState(() {
      _loadingRows = true;
      _error = null;
    });

    try {
      rows = await _driveApi.listRows(search: _searchController.text);
      loaded = true;
      if (!mounted) {
        return;
      }
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _driveErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loadingRows = false);
      }
    }

    if (!mounted || !loaded) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final viewport = MediaQuery.sizeOf(dialogContext);
        final compact = viewport.width < 640;
        return Dialog(
          insetPadding: compact
              ? const EdgeInsets.all(6)
              : const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 10 : 8),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact ? viewport.width - 12 : 1160,
              maxHeight: compact ? viewport.height - 12 : viewport.height - 44,
            ),
            child: _DriveRowsViewer(
              rows: rows,
              color: widget.module.accent,
              initialSearch: _searchController.text,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredRows = _rows
        .where((row) => row.matches(_searchController.text))
        .toList(growable: false);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.folder_copy_outlined, color: widget.module.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Google Drive / Sheets',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusPill(text: 'DB 저장', color: widget.module.accent),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _loadRows(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.manage_search_rounded),
                suffixIcon: IconButton(
                  tooltip: '검색',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: _loadRows,
                ),
                labelText: '파워 검색',
                hintText: '파일명, 탭명, 순번, text02~text20 전체 검색',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  icon: _loadingFiles
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                  label: const Text('드라이브 불러오기'),
                  onPressed: _loadingFiles ? null : _loadFiles,
                ),
                OutlinedButton.icon(
                  icon: _loadingRows
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.table_view_outlined),
                  label: const Text('보기'),
                  onPressed: _loadingRows ? null : _openRowsViewer,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _CalendarMessage(
                icon: Icons.error_outline,
                text: _error!,
                color: const Color(0xFFBA1A1A),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              _CalendarMessage(
                icon: Icons.check_circle_outline_rounded,
                text: _message!,
                color: widget.module.accent,
              ),
            ],
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Google Sheet 파일',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final file in _files)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DriveFileTile(
                      file: file,
                      color: widget.module.accent,
                      selected: _selectedFileId == file.id,
                      disabled: _importingSheetKey != null,
                      loadingSheets: _loadingSheetFileIds.contains(file.id),
                      loadedSheets: _loadedSheetFileIds.contains(file.id),
                      onTap: () => _toggleFile(file),
                    ),
                    if (_selectedFileId == file.id)
                      _DriveSheetList(
                        file: file,
                        color: widget.module.accent,
                        loading: _loadingSheetFileIds.contains(file.id),
                        loaded: _loadedSheetFileIds.contains(file.id),
                        importingSheetKey: _importingSheetKey,
                        disabled: _importingSheetKey != null,
                        sheetKeyFor: (sheetName) => _sheetKey(file, sheetName),
                        onImport: (sheetName) => _importSheet(file, sheetName),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: 16),
            _DriveRowsHeader(
              count: filteredRows.length,
              loading: _loadingRows,
              color: widget.module.accent,
            ),
            const SizedBox(height: 8),
            if (filteredRows.isEmpty)
              const _CalendarMessage(
                icon: Icons.table_rows_outlined,
                text: '저장된 Google Drive 데이터가 없습니다.',
                color: KangColors.slate,
              )
            else
              _DriveRowsTable(rows: filteredRows, color: widget.module.accent),
          ],
        ),
      ),
    );
  }

  String _driveErrorMessage(Object error) {
    final message = error.toString();
    final lowerMessage = message.toLowerCase();
    if (lowerMessage.contains('connection abort') ||
        lowerMessage.contains('connection closed') ||
        lowerMessage.contains('clientexception') ||
        lowerMessage.contains('socketexception')) {
      return 'Google Drive 연결이 일시적으로 끊겼습니다. 잠시 후 다시 시도해 주세요.';
    }
    return message
        .replaceFirst('ApiException: ', '')
        .replaceFirst('FirebaseAuthException: ', '')
        .replaceFirst('Exception: ', '');
  }
}

class _DriveFileTile extends StatelessWidget {
  const _DriveFileTile({
    required this.file,
    required this.color,
    required this.selected,
    required this.disabled,
    required this.loadingSheets,
    required this.loadedSheets,
    required this.onTap,
  });

  final GoogleDriveSheetFile file;
  final Color color;
  final bool selected;
  final bool disabled;
  final bool loadingSheets;
  final bool loadedSheets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: selected ? 6 : 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? color.withValues(alpha: 0.5) : KangColors.line,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.description_outlined, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KangColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _DriveNameLine(
                        label: '폴더명',
                        value: file.folderDisplayName,
                      ),
                      _DriveNameLine(label: '드라이브명', value: file.displayName),
                      _DriveNameLine(
                        label: 'Sheet 탭',
                        value: loadingSheets
                            ? '확인 중'
                            : loadedSheets
                            ? '${file.sheetNames.length}개'
                            : '선택 시 확인',
                      ),
                      if (file.modifiedTime != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '수정: ${file.modifiedTime}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: KangColors.slate),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  loadingSheets
                      ? Icons.sync_rounded
                      : selected
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: KangColors.slate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriveSheetList extends StatelessWidget {
  const _DriveSheetList({
    required this.file,
    required this.color,
    required this.loading,
    required this.loaded,
    required this.importingSheetKey,
    required this.disabled,
    required this.sheetKeyFor,
    required this.onImport,
  });

  final GoogleDriveSheetFile file;
  final Color color;
  final bool loading;
  final bool loaded;
  final String? importingSheetKey;
  final bool disabled;
  final String Function(String sheetName) sheetKeyFor;
  final ValueChanged<String> onImport;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(left: 50, right: 4, bottom: 12),
        child: _CalendarMessage(
          icon: Icons.sync_rounded,
          text: '${file.displayName}의 Sheet 탭을 확인하고 있습니다.',
          color: color,
        ),
      );
    }

    if (file.sheetNames.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 50, right: 4, bottom: 12),
        child: _CalendarMessage(
          icon: Icons.table_chart_outlined,
          text: loaded
              ? '이 파일에서 Sheet 탭 정보를 찾지 못했습니다.'
              : 'Sheet 탭을 확인하려면 파일을 다시 선택해 주세요.',
          color: KangColors.slate,
        ),
      );
    }

    final compact = MediaQuery.sizeOf(context).width < 520;

    return Container(
      margin: EdgeInsets.only(left: compact ? 0 : 50, right: 4, bottom: 12),
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.table_chart_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${file.displayName} Sheets',
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _StatusPill(text: '${file.sheetNames.length}개', color: color),
            ],
          ),
          const SizedBox(height: 10),
          for (final sheetName in file.sheetNames)
            _DriveSheetTile(
              sheetName: sheetName,
              color: color,
              importing: importingSheetKey == sheetKeyFor(sheetName),
              disabled: disabled && importingSheetKey != sheetKeyFor(sheetName),
              onImport: () => onImport(sheetName),
            ),
        ],
      ),
    );
  }
}

class _DriveSheetTile extends StatelessWidget {
  const _DriveSheetTile({
    required this.sheetName,
    required this.color,
    required this.importing,
    required this.disabled,
    required this.onImport,
  });

  final String sheetName;
  final Color color;
  final bool importing;
  final bool disabled;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 340;
        final title = Row(
          children: [
            Container(
              width: compact ? 40 : 34,
              height: compact ? 40 : 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.grid_on_rounded, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                sheetName,
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: KangColors.ink,
                  fontSize: compact ? 17 : 16,
                  fontWeight: FontWeight.w900,
                  height: 1.22,
                ),
              ),
            ),
          ],
        );

        final button = FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(112, 46),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          icon: importing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded, size: 21),
          label: const Text('가져오기'),
          onPressed: importing || disabled ? null : onImport,
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 12,
            vertical: compact ? 12 : 10,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KangColors.line),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: button),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    button,
                  ],
                ),
        );
      },
    );
  }
}

class _DriveRowsHeader extends StatelessWidget {
  const _DriveRowsHeader({
    required this.count,
    required this.loading,
    required this.color,
    this.title = 'google_drives 저장 데이터',
  });

  final int count;
  final bool loading;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.storage_outlined, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        _StatusPill(text: loading ? '조회 중' : '$count개', color: color),
      ],
    );
  }
}

class _DriveRowsTable extends StatelessWidget {
  const _DriveRowsTable({required this.rows, required this.color});

  final List<GoogleDriveTableRowData> rows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _DriveRowsGridTable(rows: rows, color: color);
  }
}

class _DriveRowsViewer extends StatefulWidget {
  const _DriveRowsViewer({
    required this.rows,
    required this.color,
    required this.initialSearch,
  });

  final List<GoogleDriveTableRowData> rows;
  final Color color;
  final String initialSearch;

  @override
  State<_DriveRowsViewer> createState() => _DriveRowsViewerState();
}

class _DriveRowsViewerState extends State<_DriveRowsViewer> {
  late final TextEditingController _controller;
  String _activeGroupKey = 'all';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialSearch);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchedRows = widget.rows
        .where((row) => row.matches(_controller.text))
        .toList(growable: false);
    final groups = _DriveRowsGroup.fromRows(searchedRows);
    final activeGroupKey =
        _activeGroupKey == 'all' ||
            groups.any((group) => group.key == _activeGroupKey)
        ? _activeGroupKey
        : 'all';
    final visibleRows = activeGroupKey == 'all'
        ? searchedRows
        : searchedRows
              .where((row) => _driveRowGroupKey(row) == activeGroupKey)
              .toList(growable: false);

    final driveCount = {
      for (final row in widget.rows) _driveRowName(row),
    }.where((value) => value != '-').length;
    final sheetCount = {
      for (final row in widget.rows) _driveRowGroupKey(row),
    }.where((value) => value.trim().isNotEmpty).length;

    return Container(
      color: const Color(0xFFFBFAFF),
      child: Column(
        children: [
          _DriveRowsViewerHeader(
            color: widget.color,
            rowCount: widget.rows.length,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 860;
                final compact =
                    constraints.maxWidth < 640 || constraints.maxHeight < 620;
                return Padding(
                  padding: compact
                      ? const EdgeInsets.fromLTRB(10, 10, 10, 10)
                      : const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DriveRowsViewerSearch(
                        controller: _controller,
                        color: widget.color,
                        compact: compact,
                        onChanged: (_) => setState(() {}),
                      ),
                      SizedBox(height: compact ? 8 : 12),
                      if (compact)
                        _DriveViewerStatStrip(
                          rowCount: widget.rows.length,
                          driveCount: driveCount,
                          sheetCount: sheetCount,
                          visibleCount: visibleRows.length,
                          color: widget.color,
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _DriveViewerStat(
                              icon: Icons.table_rows_outlined,
                              label: '저장 행',
                              value: '${widget.rows.length}개',
                              color: widget.color,
                            ),
                            _DriveViewerStat(
                              icon: Icons.folder_copy_outlined,
                              label: 'Drive',
                              value: '$driveCount개',
                              color: const Color(0xFF2F6FED),
                            ),
                            _DriveViewerStat(
                              icon: Icons.grid_on_rounded,
                              label: 'Sheets',
                              value: '$sheetCount개',
                              color: KangColors.mintDeep,
                            ),
                            _DriveViewerStat(
                              icon: Icons.filter_alt_outlined,
                              label: '현재 보기',
                              value: '${visibleRows.length}개',
                              color: KangColors.royalPurple,
                            ),
                          ],
                        ),
                      SizedBox(height: compact ? 8 : 14),
                      Expanded(
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: 292,
                                    child: _DriveGroupRail(
                                      groups: groups,
                                      totalCount: searchedRows.length,
                                      activeKey: activeGroupKey,
                                      color: widget.color,
                                      onSelect: (key) {
                                        setState(() => _activeGroupKey = key);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _DriveRowsResultList(
                                      rows: visibleRows,
                                      color: widget.color,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _DriveGroupDropdown(
                                    groups: groups,
                                    totalCount: searchedRows.length,
                                    activeKey: activeGroupKey,
                                    compact: compact,
                                    onChanged: (key) {
                                      if (key == null) {
                                        return;
                                      }
                                      setState(() => _activeGroupKey = key);
                                    },
                                  ),
                                  SizedBox(height: compact ? 8 : 12),
                                  Expanded(
                                    child: _DriveRowsResultList(
                                      rows: visibleRows,
                                      color: widget.color,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveRowsViewerHeader extends StatelessWidget {
  const _DriveRowsViewerHeader({required this.color, required this.rowCount});

  final Color color;
  final int rowCount;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(14, 10, 4, 10)
          : const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: KangColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 38 : 46,
            height: compact ? 38 : 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.dataset_outlined,
              color: color,
              size: compact ? 21 : 24,
            ),
          ),
          SizedBox(width: compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  compact ? '저장 데이터' : '저장 데이터 보기',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: compact ? 19 : null,
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 3),
                  Text(
                    'kang.google_drives에 저장된 Google Drive / Sheets 데이터',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: KangColors.slate),
                  ),
                ],
              ],
            ),
          ),
          _StatusPill(
            text: compact ? '$rowCount개' : '$rowCount개 행',
            color: color,
          ),
          SizedBox(width: compact ? 2 : 6),
          IconButton(
            tooltip: '닫기',
            icon: const Icon(Icons.close_rounded),
            iconSize: compact ? 22 : 24,
            constraints: BoxConstraints(
              minWidth: compact ? 40 : 48,
              minHeight: compact ? 40 : 48,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _DriveRowsViewerSearch extends StatelessWidget {
  const _DriveRowsViewerSearch({
    required this.controller,
    required this.color,
    required this.onChanged,
    this.compact = false,
  });

  final TextEditingController controller;
  final Color color;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: compact ? const TextStyle(fontSize: 14) : null,
      decoration: InputDecoration(
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
            : null,
        prefixIcon: Icon(Icons.manage_search_rounded, color: color),
        prefixIconConstraints: compact
            ? const BoxConstraints(minWidth: 40, minHeight: 40)
            : null,
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '검색어 지우기',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        labelText: '저장 데이터 검색',
        hintText: 'Drive명, Sheets명, 순번, text02~text20 전체 검색',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _DriveViewerStat extends StatelessWidget {
  const _DriveViewerStat({
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
    return Container(
      constraints: const BoxConstraints(minWidth: 156),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: KangColors.slate,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: KangColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriveViewerStatStrip extends StatelessWidget {
  const _DriveViewerStatStrip({
    required this.rowCount,
    required this.driveCount,
    required this.sheetCount,
    required this.visibleCount,
    required this.color,
  });

  final int rowCount;
  final int driveCount;
  final int sheetCount;
  final int visibleCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _DriveViewerStatChip(
            icon: Icons.table_rows_outlined,
            label: '저장',
            value: '$rowCount개',
            color: color,
          ),
          _DriveViewerStatChip(
            icon: Icons.folder_copy_outlined,
            label: 'Drive',
            value: '$driveCount개',
            color: const Color(0xFF2F6FED),
          ),
          _DriveViewerStatChip(
            icon: Icons.grid_on_rounded,
            label: 'Sheets',
            value: '$sheetCount개',
            color: KangColors.mintDeep,
          ),
          _DriveViewerStatChip(
            icon: Icons.filter_alt_outlined,
            label: '보기',
            value: '$visibleCount개',
            color: KangColors.royalPurple,
          ),
        ],
      ),
    );
  }
}

class _DriveViewerStatChip extends StatelessWidget {
  const _DriveViewerStatChip({
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
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: KangColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              color: KangColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveRowsGroup {
  const _DriveRowsGroup({
    required this.key,
    required this.driveName,
    required this.sheetName,
    required this.count,
  });

  final String key;
  final String driveName;
  final String sheetName;
  final int count;

  static List<_DriveRowsGroup> fromRows(List<GoogleDriveTableRowData> rows) {
    final counts = <String, int>{};
    final names = <String, ({String driveName, String sheetName})>{};
    for (final row in rows) {
      final key = _driveRowGroupKey(row);
      counts[key] = (counts[key] ?? 0) + 1;
      names[key] = (
        driveName: _driveRowName(row),
        sheetName: _driveSheetName(row),
      );
    }

    final groups = [
      for (final entry in counts.entries)
        _DriveRowsGroup(
          key: entry.key,
          driveName: names[entry.key]?.driveName ?? '-',
          sheetName: names[entry.key]?.sheetName ?? '-',
          count: entry.value,
        ),
    ];

    groups.sort((a, b) {
      final driveCompare = a.driveName.compareTo(b.driveName);
      if (driveCompare != 0) {
        return driveCompare;
      }
      return a.sheetName.compareTo(b.sheetName);
    });
    return groups;
  }
}

class _DriveGroupRail extends StatelessWidget {
  const _DriveGroupRail({
    required this.groups,
    required this.totalCount,
    required this.activeKey,
    required this.color,
    required this.onSelect,
  });

  final List<_DriveRowsGroup> groups;
  final int totalCount;
  final String activeKey;
  final Color color;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  'Drive / Sheets',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                _DriveGroupRailItem(
                  icon: Icons.all_inbox_outlined,
                  title: '전체 데이터',
                  subtitle: '검색 결과 전체',
                  count: totalCount,
                  selected: activeKey == 'all',
                  color: color,
                  onTap: () => onSelect('all'),
                ),
                for (final group in groups)
                  _DriveGroupRailItem(
                    icon: Icons.grid_on_rounded,
                    title: group.sheetName,
                    subtitle: group.driveName,
                    count: group.count,
                    selected: activeKey == group.key,
                    color: color,
                    onTap: () => onSelect(group.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveGroupRailItem extends StatelessWidget {
  const _DriveGroupRailItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected ? color : KangColors.slate,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? color : KangColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: KangColors.slate,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  text: '$count',
                  color: selected ? color : KangColors.slate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriveGroupDropdown extends StatelessWidget {
  const _DriveGroupDropdown({
    required this.groups,
    required this.totalCount,
    required this.activeKey,
    required this.onChanged,
    this.compact = false,
  });

  final List<_DriveRowsGroup> groups;
  final int totalCount;
  final String activeKey;
  final ValueChanged<String?> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: activeKey,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 11)
            : null,
        labelText: 'Drive / Sheets 선택',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
      ),
      items: [
        DropdownMenuItem(value: 'all', child: Text('전체 데이터 ($totalCount개)')),
        for (final group in groups)
          DropdownMenuItem(
            value: group.key,
            child: Text(
              '${group.driveName} / ${group.sheetName} (${group.count}개)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _DriveRowsResultList extends StatelessWidget {
  const _DriveRowsResultList({required this.rows, required this.color});

  final List<GoogleDriveTableRowData> rows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _DriveRowsEmptyState();
    }

    return _DriveRowsGridTable(rows: rows, color: color, fillHeight: true);
  }
}

class _DriveRowsEmptyState extends StatelessWidget {
  const _DriveRowsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(22),
          child: _CalendarMessage(
            icon: Icons.search_off_rounded,
            text: '조건에 맞는 저장 데이터가 없습니다.',
            color: KangColors.slate,
          ),
        ),
      ),
    );
  }
}

class _DriveRowsGridTable extends StatefulWidget {
  const _DriveRowsGridTable({
    required this.rows,
    required this.color,
    this.fillHeight = false,
  });

  final List<GoogleDriveTableRowData> rows;
  final Color color;
  final bool fillHeight;

  @override
  State<_DriveRowsGridTable> createState() => _DriveRowsGridTableState();
}

class _DriveRowsGridTableState extends State<_DriveRowsGridTable> {
  static const _firstColumnWidth = 96.0;
  static const _headingRowHeight = 46.0;
  static const _dataRowHeight = 54.0;
  static const _maxTableHeight = 460.0;

  final ScrollController _headerHorizontalController = ScrollController();
  final ScrollController _bodyHorizontalController = ScrollController();
  final ScrollController _frozenVerticalController = ScrollController();
  final ScrollController _bodyVerticalController = ScrollController();

  bool _syncingHorizontal = false;
  bool _syncingVertical = false;

  @override
  void dispose() {
    _headerHorizontalController.dispose();
    _bodyHorizontalController.dispose();
    _frozenVerticalController.dispose();
    _bodyVerticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sortedRows = _sortDriveRowsForDisplay(widget.rows);
    final scrollColumns = _scrollColumns(sortedRows);
    final scrollWidth = scrollColumns.fold<double>(
      0,
      (total, column) => total + column.width,
    );

    return SelectionArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KangColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final naturalHeight =
                _headingRowHeight + sortedRows.length * _dataRowHeight;
            final boundedHeight =
                widget.fillHeight && constraints.hasBoundedHeight
                ? constraints.maxHeight
                : math.min(naturalHeight, _maxTableHeight);
            final tableHeight = math.max(
              _headingRowHeight + _dataRowHeight,
              boundedHeight,
            );

            return SizedBox(
              height: tableHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _firstColumnWidth,
                    child: Column(
                      children: [
                        _gridHeaderCell(
                          '순번',
                          width: _firstColumnWidth,
                          frozen: true,
                        ),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              _syncVerticalScroll(
                                notification,
                                fromFrozenColumn: true,
                              );
                              return false;
                            },
                            child: ListView.builder(
                              controller: _frozenVerticalController,
                              primary: false,
                              itemExtent: _dataRowHeight,
                              itemCount: sortedRows.length,
                              itemBuilder: (context, index) {
                                return _gridBodyCell(
                                  _driveRowSequence(sortedRows[index]),
                                  width: _firstColumnWidth,
                                  rowIndex: index,
                                  strong: true,
                                  frozen: true,
                                  label: '순번',
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: _headingRowHeight,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              _syncHorizontalScroll(
                                notification,
                                fromHeader: true,
                              );
                              return false;
                            },
                            child: SingleChildScrollView(
                              controller: _headerHorizontalController,
                              scrollDirection: Axis.horizontal,
                              child: _gridHeaderRow(scrollColumns, scrollWidth),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Scrollbar(
                            controller: _bodyVerticalController,
                            thumbVisibility: true,
                            notificationPredicate: (notification) =>
                                notification.metrics.axis == Axis.vertical,
                            child: Scrollbar(
                              controller: _bodyHorizontalController,
                              thumbVisibility: true,
                              notificationPredicate: (notification) =>
                                  notification.metrics.axis == Axis.horizontal,
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  _syncHorizontalScroll(
                                    notification,
                                    fromHeader: false,
                                  );
                                  return false;
                                },
                                child: SingleChildScrollView(
                                  controller: _bodyHorizontalController,
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: scrollWidth,
                                    child:
                                        NotificationListener<
                                          ScrollNotification
                                        >(
                                          onNotification: (notification) {
                                            _syncVerticalScroll(
                                              notification,
                                              fromFrozenColumn: false,
                                            );
                                            return false;
                                          },
                                          child: ListView.builder(
                                            controller: _bodyVerticalController,
                                            primary: false,
                                            itemExtent: _dataRowHeight,
                                            itemCount: sortedRows.length,
                                            itemBuilder: (context, index) {
                                              return _gridDataRow(
                                                sortedRows[index],
                                                index,
                                                scrollColumns,
                                                scrollWidth,
                                              );
                                            },
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<_DriveRowsGridColumn> _scrollColumns(
    List<GoogleDriveTableRowData> rows,
  ) {
    return [
      for (var index = 1; index < 20; index++)
        if (_hasTextColumnData(rows, index))
          _DriveRowsGridColumn(
            'text${(index + 1).toString().padLeft(2, '0')}',
            _textColumnWidthFor(rows, index),
            (row) => _driveTextValue(row, index),
          ),
      _DriveRowsGridColumn(
        'Drive명',
        _columnWidthFor(rows, _driveRowName, minWidth: 180, maxWidth: 260),
        _driveRowName,
        strong: true,
      ),
      _DriveRowsGridColumn(
        'Sheets명',
        _columnWidthFor(rows, _driveSheetName, minWidth: 160, maxWidth: 240),
        _driveSheetName,
        strong: true,
      ),
    ];
  }

  bool _hasTextColumnData(List<GoogleDriveTableRowData> rows, int index) {
    return rows.any((row) => _hasVisibleCellData(_driveTextValue(row, index)));
  }

  bool _hasVisibleCellData(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty && normalized != '-';
  }

  double _textColumnWidthFor(List<GoogleDriveTableRowData> rows, int index) {
    return switch (index) {
      1 => _columnWidthFor(
        rows,
        (row) => _driveTextValue(row, index),
        minWidth: 240,
        maxWidth: 440,
        charWidth: 8.4,
      ),
      2 => _columnWidthFor(
        rows,
        (row) => _driveTextValue(row, index),
        minWidth: 220,
        maxWidth: 380,
        charWidth: 8.2,
      ),
      3 => _columnWidthFor(
        rows,
        (row) => _driveTextValue(row, index),
        minWidth: 200,
        maxWidth: 340,
        charWidth: 8.0,
      ),
      _ => _columnWidthFor(
        rows,
        (row) => _driveTextValue(row, index),
        minWidth: 150,
        maxWidth: 280,
        charWidth: 7.8,
      ),
    };
  }

  double _columnWidthFor(
    List<GoogleDriveTableRowData> rows,
    String Function(GoogleDriveTableRowData row) valueFor, {
    required double minWidth,
    required double maxWidth,
    double charWidth = 8.0,
  }) {
    if (rows.isEmpty) {
      return minWidth;
    }

    final scores = [
      for (final row in rows)
        if (_hasVisibleCellData(valueFor(row))) _textWidthScore(valueFor(row)),
    ]..sort();
    if (scores.isEmpty) {
      return minWidth;
    }

    final score = scores.length < 80
        ? scores.last
        : scores[(scores.length * 0.9).floor().clamp(0, scores.length - 1)];
    final width = 42 + score * charWidth;
    return width.clamp(minWidth, maxWidth).toDouble();
  }

  double _textWidthScore(String value) {
    var currentLine = 0.0;
    var longestLine = 0.0;
    for (final rune in value.runes) {
      if (rune == 10 || rune == 13) {
        longestLine = math.max(longestLine, currentLine);
        currentLine = 0;
        continue;
      }
      currentLine += _runeWidthScore(rune);
    }
    return math.max(longestLine, currentLine);
  }

  double _runeWidthScore(int rune) {
    if (rune == 32) {
      return 0.55;
    }
    if ((rune >= 0xAC00 && rune <= 0xD7A3) ||
        (rune >= 0x3130 && rune <= 0x318F) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3040 && rune <= 0x30FF)) {
      return 1.65;
    }
    if (rune >= 48 && rune <= 57) {
      return 0.9;
    }
    if ((rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122)) {
      return 0.95;
    }
    return 0.8;
  }

  Widget _gridHeaderRow(
    List<_DriveRowsGridColumn> columns,
    double scrollWidth,
  ) {
    return SizedBox(
      width: scrollWidth,
      height: _headingRowHeight,
      child: Row(
        children: [
          for (final column in columns)
            _gridHeaderCell(column.label, width: column.width),
        ],
      ),
    );
  }

  Widget _gridDataRow(
    GoogleDriveTableRowData row,
    int rowIndex,
    List<_DriveRowsGridColumn> columns,
    double scrollWidth,
  ) {
    return SizedBox(
      width: scrollWidth,
      height: _dataRowHeight,
      child: Row(
        children: [
          for (final column in columns)
            _gridBodyCell(
              column.valueFor(row),
              width: column.width,
              rowIndex: rowIndex,
              strong: column.strong,
              label: column.label,
            ),
        ],
      ),
    );
  }

  Widget _gridHeaderCell(
    String label, {
    required double width,
    bool frozen = false,
  }) {
    return Container(
      width: width,
      height: _headingRowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: frozen
            ? widget.color.withValues(alpha: 0.16)
            : widget.color.withValues(alpha: 0.1),
        border: Border(
          right: BorderSide(color: KangColors.line.withValues(alpha: 0.7)),
          bottom: const BorderSide(color: KangColors.line),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: KangColors.royalPurple,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _gridBodyCell(
    String value, {
    required double width,
    required int rowIndex,
    bool strong = false,
    bool frozen = false,
    String? label,
  }) {
    final alternateColor = KangColors.purpleWash.withValues(alpha: 0.42);
    final baseColor = rowIndex.isEven ? Colors.white : alternateColor;
    final backgroundColor = frozen
        ? Color.alphaBlend(widget.color.withValues(alpha: 0.04), baseColor)
        : baseColor;
    final displayValue = value.isEmpty ? '-' : value;
    final normalizedValue = value.trim();
    final canOpenDetail =
        normalizedValue.isNotEmpty &&
        normalizedValue != '-' &&
        (normalizedValue.length > 18 || normalizedValue.contains('\n'));
    final text = Text(
      displayValue,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: strong ? KangColors.ink : KangColors.slate,
        fontSize: 13,
        fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
        height: 1.24,
      ),
    );
    final content = canOpenDetail
        ? Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 4),
              Tooltip(
                message: '전체 보기',
                waitDuration: const Duration(milliseconds: 350),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    size: 14,
                    color: widget.color.withValues(alpha: 0.82),
                  ),
                  onPressed: () => _showCellDetail(label ?? '', value),
                ),
              ),
            ],
          )
        : text;

    return Container(
      width: width,
      height: _dataRowHeight,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(
        horizontal: canOpenDetail ? 10 : 14,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          right: BorderSide(color: KangColors.line.withValues(alpha: 0.55)),
          bottom: const BorderSide(color: KangColors.line),
        ),
      ),
      child: content,
    );
  }

  Future<void> _showCellDetail(String label, String value) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final viewport = MediaQuery.sizeOf(dialogContext);
        final compact = viewport.width < 640;
        return Dialog(
          alignment: compact ? Alignment.bottomCenter : Alignment.center,
          insetPadding: compact
              ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 12 : 8),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact ? viewport.width - 16 : 720,
              maxHeight: compact
                  ? viewport.height * 0.72
                  : viewport.height - 48,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: compact
                      ? const EdgeInsets.fromLTRB(14, 10, 4, 10)
                      : const EdgeInsets.fromLTRB(18, 14, 8, 14),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    border: Border(bottom: BorderSide(color: KangColors.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label.isEmpty ? '셀 내용' : label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: KangColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: compact
                        ? const EdgeInsets.fromLTRB(14, 14, 14, 18)
                        : const EdgeInsets.all(18),
                    child: SelectableText(
                      value,
                      style: TextStyle(
                        color: KangColors.ink,
                        fontSize: compact ? 14.5 : 15,
                        fontWeight: FontWeight.w700,
                        height: 1.55,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _syncHorizontalScroll(
    ScrollNotification notification, {
    required bool fromHeader,
  }) {
    if (_syncingHorizontal || notification.metrics.axis != Axis.horizontal) {
      return;
    }

    final target = fromHeader
        ? _bodyHorizontalController
        : _headerHorizontalController;
    if (!target.hasClients) {
      return;
    }

    final nextOffset = notification.metrics.pixels
        .clamp(0.0, target.position.maxScrollExtent)
        .toDouble();
    if ((target.offset - nextOffset).abs() < 0.5) {
      return;
    }

    _syncingHorizontal = true;
    target.jumpTo(nextOffset);
    _syncingHorizontal = false;
  }

  void _syncVerticalScroll(
    ScrollNotification notification, {
    required bool fromFrozenColumn,
  }) {
    if (_syncingVertical || notification.metrics.axis != Axis.vertical) {
      return;
    }

    final target = fromFrozenColumn
        ? _bodyVerticalController
        : _frozenVerticalController;
    if (!target.hasClients) {
      return;
    }

    final nextOffset = notification.metrics.pixels
        .clamp(0.0, target.position.maxScrollExtent)
        .toDouble();
    if ((target.offset - nextOffset).abs() < 0.5) {
      return;
    }

    _syncingVertical = true;
    target.jumpTo(nextOffset);
    _syncingVertical = false;
  }
}

class _DriveRowsGridColumn {
  const _DriveRowsGridColumn(
    this.label,
    this.width,
    this.valueFor, {
    this.strong = false,
  });

  final String label;
  final double width;
  final String Function(GoogleDriveTableRowData row) valueFor;
  final bool strong;
}

class _DriveNameLine extends StatelessWidget {
  const _DriveNameLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: const TextStyle(
              color: KangColors.royalPurple,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: KangColors.slate,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

String _driveRowName(GoogleDriveTableRowData row) {
  final value = (row.driveName ?? '').trim();
  return value.isEmpty ? '-' : value;
}

String _driveSheetName(GoogleDriveTableRowData row) {
  final value = (row.tabName ?? '').trim();
  return value.isEmpty ? '-' : value;
}

String _driveRowSequence(GoogleDriveTableRowData row) {
  return _driveTextValue(row, 0);
}

String _driveTextValue(GoogleDriveTableRowData row, int index) {
  if (index < 0 || index >= row.values.length) {
    return '';
  }
  return (row.values[index] ?? '').trim();
}

List<GoogleDriveTableRowData> _sortDriveRowsForDisplay(
  List<GoogleDriveTableRowData> rows,
) {
  final sortedRows = rows.toList(growable: false);
  sortedRows.sort(_compareDriveRowsForDisplay);
  return sortedRows;
}

int _compareDriveRowsForDisplay(
  GoogleDriveTableRowData a,
  GoogleDriveTableRowData b,
) {
  final driveCompare = _driveRowName(a).compareTo(_driveRowName(b));
  if (driveCompare != 0) {
    return driveCompare;
  }

  final sheetCompare = _driveSheetName(a).compareTo(_driveSheetName(b));
  if (sheetCompare != 0) {
    return sheetCompare;
  }

  final titleCompare = _driveRowTitlePriority(
    a,
  ).compareTo(_driveRowTitlePriority(b));
  if (titleCompare != 0) {
    return titleCompare;
  }

  final aNumber = _driveRowSequenceNumber(a);
  final bNumber = _driveRowSequenceNumber(b);
  if (aNumber != null && bNumber != null) {
    final numberCompare = aNumber.compareTo(bNumber);
    if (numberCompare != 0) {
      return numberCompare;
    }
  } else if (aNumber != null) {
    return -1;
  } else if (bNumber != null) {
    return 1;
  }

  final sequenceCompare = _driveRowSequence(a).compareTo(_driveRowSequence(b));
  if (sequenceCompare != 0) {
    return sequenceCompare;
  }

  return a.id.compareTo(b.id);
}

int _driveRowTitlePriority(GoogleDriveTableRowData row) {
  return _driveRowSequence(row) == '순번' ? 0 : 1;
}

num? _driveRowSequenceNumber(GoogleDriveTableRowData row) {
  final normalized = _driveRowSequence(row).replaceAll(',', '').trim();
  if (normalized.isEmpty) {
    return null;
  }
  return num.tryParse(normalized);
}

String _driveRowGroupKey(GoogleDriveTableRowData row) {
  return '${_driveRowName(row)}\u001F${_driveSheetName(row)}';
}

class _CalendarFeaturePanel extends StatefulWidget {
  const _CalendarFeaturePanel({required this.module});

  final _HomeModule module;

  @override
  State<_CalendarFeaturePanel> createState() => _CalendarFeaturePanelState();
}

class _CalendarFeaturePanelState extends State<_CalendarFeaturePanel> {
  final GoogleCalendarService _calendarService = GoogleCalendarService();

  bool _loading = false;
  GoogleCalendarPreview? _preview;
  String? _error;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDate(_selectedDate, interactive: false);
    });
  }

  Future<void> _connect() async {
    await _loadDate(_selectedDate, interactive: true);
  }

  Future<void> _loadDate(DateTime date, {bool interactive = false}) async {
    if (_loading) {
      return;
    }

    final normalizedDate = DateTime(date.year, date.month, date.day);
    setState(() {
      _loading = true;
      _error = null;
      _selectedDate = normalizedDate;
    });

    try {
      final preview = await _calendarService.loadEventsForDate(
        normalizedDate,
        interactive: interactive,
      );
      if (!mounted) {
        return;
      }
      setState(() => _preview = preview);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _calendarErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _moveDate(int days) {
    return _loadDate(_selectedDate.add(Duration(days: days)));
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      await _loadDate(pickedDate);
    }
  }

  Future<void> _goToday() {
    final now = DateTime.now();
    return _loadDate(DateTime(now.year, now.month, now.day));
  }

  Future<void> _openCalendar() async {
    final opened = await openGoogleCalendar(date: _selectedDate);
    if (!opened && mounted) {
      _showCalendarLauncherError('Google Calendar를 열 수 없습니다.');
    }
  }

  Future<void> _openCalendarCreate() async {
    final opened = await openGoogleCalendarEventCreate(date: _selectedDate);
    if (!opened && mounted) {
      _showCalendarLauncherError('Google Calendar 일정 추가 화면을 열 수 없습니다.');
    }
  }

  void _showCalendarLauncherError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final events = _preview?.events ?? const <GoogleCalendarEvent>[];
    final connected = _preview != null && _error == null;

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
                Icon(
                  Icons.calendar_month_outlined,
                  color: widget.module.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Google Calendar',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusPill(
                  text: connected ? '연결됨' : '연결 필요',
                  color: widget.module.accent,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CalendarDateNavigator(
              date: _selectedDate,
              loading: _loading,
              onPrevious: () => _moveDate(-1),
              onNext: () => _moveDate(1),
              onPickDate: _pickDate,
              onToday: _goToday,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
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
                      : const Icon(Icons.sync_rounded),
                  label: Text(connected ? '일정 새로고침' : 'Google Calendar 연결'),
                  onPressed: _loading ? null : _connect,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('캘린더 열기'),
                  onPressed: _openCalendar,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('일정 추가'),
                  onPressed: _openCalendarCreate,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _CalendarMessage(
                icon: Icons.error_outline,
                text: _error!,
                color: const Color(0xFFBA1A1A),
              ),
            ],
            if (connected) ...[
              const SizedBox(height: 16),
              _CalendarDayHeader(
                date: _selectedDate,
                eventCount: events.length,
                color: widget.module.accent,
              ),
              const SizedBox(height: 12),
              if (events.isEmpty)
                const _CalendarMessage(
                  icon: Icons.event_available_outlined,
                  text: '선택한 날짜에 등록된 일정이 없습니다.',
                  color: KangColors.slate,
                )
              else
                for (final event in events) _CalendarEventTile(event: event),
            ],
          ],
        ),
      ),
    );
  }

  String _calendarErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'popup-closed-by-user' ||
        'web-context-cancelled' ||
        'cancelled-popup-request' => 'Google Calendar 권한 요청이 취소되었습니다.',
        'missing-google-access-token' =>
          '아직 Calendar 권한 토큰이 없습니다. Google Calendar 연결 버튼을 눌러 권한을 허용해 주세요.',
        'calendar-scope-denied' =>
          'Google Calendar 권한이 거부되었거나 만료되었습니다. 다시 연결해 주세요.',
        'account-exists-with-different-credential' =>
          '이 Google 계정은 다른 Firebase 계정에 이미 연결되어 있습니다.',
        _ => error.message ?? 'Google Calendar 연결에 실패했습니다.',
      };
    }
    return error.toString();
  }
}

class _CalendarDateNavigator extends StatelessWidget {
  const _CalendarDateNavigator({
    required this.date,
    required this.loading,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
    required this.onToday,
  });

  final DateTime date;
  final bool loading;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickDate;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final dateSelector = _CalendarDateSelectButton(
          date: date,
          loading: loading,
          onPressed: onPickDate,
        );
        final previousButton = _CalendarMoveButton(
          icon: Icons.chevron_left_rounded,
          label: '전날',
          loading: loading,
          onPressed: onPrevious,
        );
        final nextButton = _CalendarMoveButton(
          icon: Icons.chevron_right_rounded,
          label: '다음날',
          loading: loading,
          onPressed: onNext,
          iconAfterLabel: true,
        );
        final todayButton = OutlinedButton.icon(
          icon: const Icon(Icons.today_outlined),
          label: const Text('오늘'),
          onPressed: loading ? null : onToday,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(88, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dateSelector,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: previousButton),
                  const SizedBox(width: 8),
                  todayButton,
                  const SizedBox(width: 8),
                  Expanded(child: nextButton),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            previousButton,
            const SizedBox(width: 10),
            Expanded(child: dateSelector),
            const SizedBox(width: 10),
            nextButton,
            const SizedBox(width: 10),
            todayButton,
          ],
        );
      },
    );
  }
}

class _CalendarDateSelectButton extends StatelessWidget {
  const _CalendarDateSelectButton({
    required this.date,
    required this.loading,
    required this.onPressed,
  });

  final DateTime date;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = !loading;

    return Material(
      color: enabled
          ? KangColors.royalPurple.withValues(alpha: 0.08)
          : KangColors.line.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onPressed : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: KangColors.royalPurple.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: KangColors.royalPurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '선택 날짜',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: KangColors.slate,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _CalendarDateText.full(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KangColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.expand_more_rounded,
                color: KangColors.royalPurple,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarMoveButton extends StatelessWidget {
  const _CalendarMoveButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onPressed,
    this.iconAfterLabel = false,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final bool iconAfterLabel;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, size: 22),
      const SizedBox(width: 4),
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ];

    return OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(94, 64),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: iconAfterLabel ? children.reversed.toList() : children,
      ),
    );
  }
}

class _CalendarDayHeader extends StatelessWidget {
  const _CalendarDayHeader({
    required this.date,
    required this.eventCount,
    required this.color,
  });

  final DateTime date;
  final int eventCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.view_day_outlined, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_CalendarDateText.short(date)} 일정',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: KangColors.ink,
                ),
              ),
            ),
            Text(
              '$eventCount개',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarEventTile extends StatelessWidget {
  const _CalendarEventTile({required this.event});

  final GoogleCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
        boxShadow: [
          BoxShadow(
            color: KangColors.deepPurple.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: KangColors.mintSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _formatEventStart(event),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KangColors.royalPurple,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: KangColors.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: KangColors.slate,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _formatEventRange(event),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: KangColors.slate,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 15,
                      color: KangColors.slate,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        event.calendarTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: KangColors.slate,
                        ),
                      ),
                    ),
                  ],
                ),
                if (event.location != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 15,
                        color: KangColors.slate,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: KangColors.slate),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatEventStart(GoogleCalendarEvent event) {
    if (event.allDay) {
      return '종일';
    }

    final start = event.start;
    if (start == null) {
      return '시간 없음';
    }

    final local = start.toLocal();
    return '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _formatEventRange(GoogleCalendarEvent event) {
    if (event.allDay) {
      return '종일 일정';
    }

    final start = event.start?.toLocal();
    final end = event.end?.toLocal();
    if (start == null) {
      return '시간이 지정되지 않았습니다.';
    }

    if (end == null) {
      return '${_two(start.hour)}:${_two(start.minute)}';
    }

    return '${_two(start.hour)}:${_two(start.minute)} - '
        '${_two(end.hour)}:${_two(end.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _CalendarDateText {
  const _CalendarDateText._();

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  static String full(DateTime date) {
    return '${date.year}.${_two(date.month)}.${_two(date.day)} '
        '(${_weekdays[date.weekday - 1]})';
  }

  static String short(DateTime date) {
    return '${_two(date.month)}.${_two(date.day)} '
        '(${_weekdays[date.weekday - 1]})';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _CalendarMessage extends StatelessWidget {
  const _CalendarMessage({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color, fontSize: 13),
          ),
        ),
      ],
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
    this.kind = _HomeModuleKind.placeholder,
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

  final _HomeModuleKind kind;
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

enum _HomeModuleKind {
  calendar,
  drive,
  keep,
  university,
  marketCap,
  financial,
  subway,
  stockTrading,
  placeholder,
}
