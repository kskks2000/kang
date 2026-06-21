import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
import '../services/stock_market_api.dart';
import '../services/subway_api.dart';
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
        title: '주식 거래',
        subtitle: '거래 대시보드',
        status: '준비중',
        icon: Icons.show_chart_rounded,
        accent: Color(0xFF15213F),
        surface: Color(0xFFEFF4FF),
        kind: _HomeModuleKind.stockTrading,
        screenTitle: '주식 거래 대시보드',
        screenSubtitle: '관심종목, 주문, 체결 현황을 연결할 준비 영역',
        screenIcon: Icons.show_chart_rounded,
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
                    'Google 연동이 활성화되었습니다.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '캘린더, 파일, 대학 정보를 Kang에서 바로 확인할 수 있습니다.',
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
                child: module.kind == _HomeModuleKind.calendar
                    ? _CalendarModuleTile(
                        module: module,
                        preview: calendarPreview,
                        onRefresh: onCalendarPreviewRefresh,
                      )
                    : _ModuleTile(module: module),
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
        onTap: () => _openModule(context),
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
    return Material(
      color: Colors.white.withValues(alpha: 0.84),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openCalendar(context),
        child: Ink(
          height: 184,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: module.accent.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: KangColors.deepPurple.withValues(alpha: 0.06),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
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
              const SizedBox(height: 13),
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
                '오늘 Google Calendar 일정',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  color: KangColors.slate,
                ),
              ),
              const SizedBox(height: 8),
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
                        for (final event in events.take(2))
                          _CalendarHomeEventLine(event: event),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
        const SizedBox(height: 8),
        Text(
          message,
          maxLines: 2,
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

class _StockTradingFullScreenState extends State<_StockTradingFullScreen> {
  var _selectedMarket = _StockTradingMarket.domestic;

  _StockTradingMarketConfig get _config =>
      _StockTradingMarketConfig.byMarket(_selectedMarket);

  @override
  Widget build(BuildContext context) {
    final config = _config;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: Column(
          children: [
            _StockTradingTopBar(
              config: config,
              selectedMarket: _selectedMarket,
              onMarketChanged: (market) {
                setState(() => _selectedMarket = market);
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1100;
                  final medium = constraints.maxWidth >= 820;
                  final padding = constraints.maxWidth < 720 ? 10.0 : 14.0;

                  if (!medium) {
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 420,
                            child: _StockTradingWatchlistPanel(config: config),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 560,
                            child: _StockTradingMarketBoard(config: config),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 390,
                            child: _StockTradingOrderPanel(config: config),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 210,
                            child: _StockTradingExecutionPanel(config: config),
                          ),
                        ],
                      ),
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.all(padding),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: wide ? 292 : 252,
                          child: _StockTradingWatchlistPanel(config: config),
                        ),
                        SizedBox(width: padding),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                flex: 6,
                                child: _StockTradingMarketBoard(config: config),
                              ),
                              SizedBox(height: padding),
                              Expanded(
                                flex: 3,
                                child: _StockTradingExecutionPanel(
                                  config: config,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: padding),
                        SizedBox(
                          width: wide ? 336 : 304,
                          child: _StockTradingOrderPanel(config: config),
                        ),
                      ],
                    ),
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

class _StockTradingTopBar extends StatelessWidget {
  const _StockTradingTopBar({
    required this.config,
    required this.selectedMarket,
    required this.onMarketChanged,
  });

  final _StockTradingMarketConfig config;
  final _StockTradingMarket selectedMarket;
  final ValueChanged<_StockTradingMarket> onMarketChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: KangColors.line)),
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
              color: config.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
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
          _StatusPill(text: '데모 구성', color: config.color),
        ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: KangColors.line)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 19, color: color),
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

class _StockTradingWatchlistPanel extends StatelessWidget {
  const _StockTradingWatchlistPanel({required this.config});

  final _StockTradingMarketConfig config;

  @override
  Widget build(BuildContext context) {
    final symbols = config.title == '국내 주식'
        ? const [
            ('005930', '삼성전자', '+0.42%'),
            ('000660', 'SK하이닉스', '-0.18%'),
            ('035420', 'NAVER', '+1.12%'),
            ('035720', '카카오', '-0.64%'),
          ]
        : const [
            ('NVDA', 'NVIDIA', '+0.05%'),
            ('AAPL', 'Apple', '-0.21%'),
            ('MSFT', 'Microsoft', '+0.38%'),
            ('TSLA', 'Tesla', '+1.44%'),
          ];

    return _StockTradingPanel(
      title: '관심종목',
      icon: Icons.star_border_rounded,
      color: config.color,
      trailing: _StatusPill(text: config.badge, color: config.color),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, color: config.color),
                hintText: '종목명 · 코드 검색',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemBuilder: (context, index) {
                final item = symbols[index];
                final positive = item.$3.startsWith('+');
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: config.color.withValues(
                      alpha: index == 0 ? 0.08 : 0.03,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: config.color.withValues(
                        alpha: index == 0 ? 0.18 : 0.08,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$1,
                              style: const TextStyle(
                                color: KangColors.ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: KangColors.slate),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        item.$3,
                        style: TextStyle(
                          color: positive
                              ? KangColors.mintDeep
                              : Colors.red.shade600,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemCount: symbols.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingMarketBoard extends StatelessWidget {
  const _StockTradingMarketBoard({required this.config});

  final _StockTradingMarketConfig config;

  @override
  Widget build(BuildContext context) {
    return _StockTradingPanel(
      title: '시세 · 차트 · 호가',
      icon: Icons.candlestick_chart_rounded,
      color: config.color,
      trailing: const Text(
        '실시간 연결 예정',
        style: TextStyle(
          color: KangColors.slate,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final chart = _StockTradingChartPlaceholder(color: config.color);
          final quote = _StockTradingQuotePlaceholder(config: config);

          if (compact) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SizedBox(height: 260, child: chart),
                  const SizedBox(height: 12),
                  SizedBox(height: 240, child: quote),
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
                Expanded(flex: 3, child: quote),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StockTradingChartPlaceholder extends StatelessWidget {
  const _StockTradingChartPlaceholder({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        painter: _StockTradingChartPainter(color: color),
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '차트 영역',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '종목 선택 시 실시간 차트가 표시됩니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.66),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTradingQuotePlaceholder extends StatelessWidget {
  const _StockTradingQuotePlaceholder({required this.config});

  final _StockTradingMarketConfig config;

  @override
  Widget build(BuildContext context) {
    final rows = config.title == '국내 주식'
        ? const [
            ('매도 3', '72,300'),
            ('매도 2', '72,200'),
            ('매도 1', '72,100'),
            ('매수 1', '72,000'),
            ('매수 2', '71,900'),
          ]
        : const [
            ('Ask 3', '212.90'),
            ('Ask 2', '212.75'),
            ('Ask 1', '212.63'),
            ('Bid 1', '212.50'),
            ('Bid 2', '212.41'),
          ];

    return Container(
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: config.color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '호가 보드',
              style: TextStyle(
                color: config.color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Divider(height: 1, color: KangColors.line),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final ask = index < 3;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.$1,
                          style: TextStyle(
                            color: ask ? Colors.red.shade600 : config.color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        row.$2,
                        style: const TextStyle(
                          color: KangColors.ink,
                          fontWeight: FontWeight.w900,
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

class _StockTradingOrderPanel extends StatelessWidget {
  const _StockTradingOrderPanel({required this.config});

  final _StockTradingMarketConfig config;

  @override
  Widget build(BuildContext context) {
    return _StockTradingPanel(
      title: '주문 패널',
      icon: Icons.price_change_outlined,
      color: config.color,
      trailing: _StatusPill(text: config.badge, color: config.color),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'buy', label: Text('매수')),
                ButtonSegment(value: 'sell', label: Text('매도')),
              ],
              selected: const {'buy'},
              onSelectionChanged: (_) {},
            ),
            const SizedBox(height: 14),
            _StockTradingReadonlyField(label: '종목', value: '선택된 종목 없음'),
            const SizedBox(height: 10),
            _StockTradingReadonlyField(
              label: '주문 가격',
              value: config.title == '국내 주식' ? '0 KRW' : '0 USD',
            ),
            const SizedBox(height: 10),
            _StockTradingReadonlyField(label: '수량', value: '0'),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('거래 API 연결 전'),
              onPressed: null,
            ),
            const SizedBox(height: 12),
            _CalendarMessage(
              icon: Icons.security_rounded,
              text: '실제 주문 연결 전에는 주문 버튼을 비활성화합니다.',
              color: config.color,
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTradingReadonlyField extends StatelessWidget {
  const _StockTradingReadonlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: value,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _StockTradingExecutionPanel extends StatelessWidget {
  const _StockTradingExecutionPanel({required this.config});

  final _StockTradingMarketConfig config;

  @override
  Widget build(BuildContext context) {
    return _StockTradingPanel(
      title: '체결 · 미체결 · 잔고',
      icon: Icons.receipt_long_outlined,
      color: config.color,
      trailing: const Text(
        '데이터 연결 예정',
        style: TextStyle(
          color: KangColors.slate,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: _StockTradingSummaryBox(
                title: '체결 현황',
                value: '0건',
                color: config.color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StockTradingSummaryBox(
                title: '미체결',
                value: '0건',
                color: config.color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StockTradingSummaryBox(
                title: config.balanceTitle,
                value: config.balanceValue,
                color: config.color,
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
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12)),
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
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTradingChartPainter extends CustomPainter {
  const _StockTradingChartPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    path.moveTo(0, size.height * 0.68);
    path.cubicTo(
      size.width * 0.18,
      size.height * 0.58,
      size.width * 0.24,
      size.height * 0.78,
      size.width * 0.42,
      size.height * 0.48,
    );
    path.cubicTo(
      size.width * 0.58,
      size.height * 0.22,
      size.width * 0.72,
      size.height * 0.62,
      size.width,
      size.height * 0.34,
    );
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _StockTradingChartPainter oldDelegate) {
    return oldDelegate.color != color;
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
                        '국내와 해외 거래 화면을 나누어 붙일 자리입니다.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: KangColors.slate,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(text: '준비중', color: widget.module.accent),
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
        color: KangColors.purpleWash.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line.withValues(alpha: 0.9)),
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
        color: config.color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: config.color.withValues(alpha: 0.14)),
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
        color: color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12)),
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
