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
import '../services/google_calendar_service.dart';
import '../services/google_drive_api.dart';
import '../services/google_keep_service.dart';
import '../services/google_keep_launcher.dart';
import '../services/stock_market_api.dart';
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                      prefixIcon: const Icon(Icons.manage_search_rounded),
                      labelText: '종목 검색',
                      hintText: '회사명, 티커, 국가, 섹터, 산업',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
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
    final details = [
      company.country,
      company.sector,
      company.industry,
    ].where((value) => value.isNotEmpty).join(' · ');

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
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#${company.rank}',
                  style: TextStyle(
                    color: color,
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
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        details,
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
              const SizedBox(width: 8),
              _StatusPill(text: company.symbol, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MarketCapMetric(
                label: '시가총액',
                value: _formatUsdCompact(company.marketCap),
              ),
              _MarketCapMetric(
                label: '주가',
                value: _formatUsdPrice(company.price),
              ),
              _MarketCapMetric(
                label: '일일변동',
                value: _formatSignedPercent(change),
                valueColor: changeColor,
              ),
              _MarketCapMetric(
                label: 'P/E',
                value: company.peRatio == null
                    ? '-'
                    : _trimDecimal(company.peRatio!, digits: 2),
              ),
              _MarketCapMetric(
                label: '매출',
                value: _formatUsdCompact(company.revenue),
              ),
            ],
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
    this.valueColor = KangColors.ink,
  });

  final String label;
  final String value;
  final Color valueColor;

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
            style: TextStyle(color: valueColor, fontWeight: FontWeight.w900),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _UniversitySummaryTile(
              icon: Icons.account_balance_outlined,
              label: '미 10년물',
              value: _formatRatePercent(tenYear?.rate),
              color: color,
            ),
            _UniversitySummaryTile(
              icon: Icons.timeline_rounded,
              label: '10Y-2Y',
              value: _formatSpreadPercent(tenTwoSpread?.value),
              color: KangColors.royalPurple,
            ),
            _UniversitySummaryTile(
              icon: Icons.currency_exchange_rounded,
              label: 'USD/KRW',
              value: _formatFxRate(usdKrw?.rate),
              color: KangColors.mintDeep,
            ),
            _UniversitySummaryTile(
              icon: Icons.show_chart_rounded,
              label: 'Nasdaq 선물',
              value: _formatSignedPercent(nasdaqFuture?.changePercent),
              color: (nasdaqFuture?.changePercent ?? 0) >= 0
                  ? KangColors.mintDeep
                  : Colors.red.shade600,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _UniversitySourceNote(
          color: color,
          title: 'U.S. Treasury · Frankfurter/ECB · Yahoo Finance Chart Data',
          description:
              '미국채 수익률 곡선, 주요 통화 환율, 미국 지수선물과 매크로 지표를 한 화면에서 확인합니다. '
              '국채/환율 기준일: ${dataset.summary.treasuryDate} / ${dataset.summary.exchangeRateDate}',
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
        _DriveRowsHeader(
          count: dataset.treasuryRates.length,
          loading: false,
          color: color,
          title: '미국채 수익률 곡선',
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
        _DriveRowsHeader(
          count: dataset.exchangeRates.length,
          loading: false,
          color: color,
          title: '주요 환율',
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
                mainAxisExtent: 112,
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
        _DriveRowsHeader(
          count: dataset.futures.length,
          loading: false,
          color: color,
          title: '미국 선물·매크로 지표',
        ),
        const SizedBox(height: 8),
        for (final quote in dataset.futures)
          _FinancialFutureTile(quote: quote, color: color),
      ],
    );
  }
}

class _TreasuryRateTile extends StatelessWidget {
  const _TreasuryRateTile({required this.rate, required this.color});

  final TreasuryRate rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final changeColor = (rate.change ?? 0) >= 0
        ? KangColors.mintDeep
        : Colors.red.shade600;

    return Container(
      width: 118,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
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
          const SizedBox(height: 8),
          Text(
            _formatRatePercent(rate.rate),
            style: const TextStyle(
              color: KangColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatBasisPointChange(rate.change),
            style: TextStyle(
              color: changeColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
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
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.line),
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
              const Icon(
                Icons.currency_exchange_rounded,
                size: 16,
                color: KangColors.slate,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatFxRate(rate.rate),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KangColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rate.label,
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
              _StatusPill(text: quote.group, color: color),
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
            ],
          ),
        ],
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
        onPressed: openGoogleKeep,
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
                      onTap: () {
                        setState(() {
                          _selectedFileId = _selectedFileId == file.id
                              ? null
                              : file.id;
                        });
                      },
                    ),
                    if (_selectedFileId == file.id)
                      _DriveSheetList(
                        file: file,
                        color: widget.module.accent,
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
    required this.onTap,
  });

  final GoogleDriveSheetFile file;
  final Color color;
  final bool selected;
  final bool disabled;
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
                        value: file.sheetNames.isEmpty
                            ? '0개'
                            : '${file.sheetNames.length}개',
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
                  selected
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
    required this.importingSheetKey,
    required this.disabled,
    required this.sheetKeyFor,
    required this.onImport,
  });

  final GoogleDriveSheetFile file;
  final Color color;
  final String? importingSheetKey;
  final bool disabled;
  final String Function(String sheetName) sheetKeyFor;
  final ValueChanged<String> onImport;

  @override
  Widget build(BuildContext context) {
    if (file.sheetNames.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(left: 50, right: 4, bottom: 12),
        child: _CalendarMessage(
          icon: Icons.table_chart_outlined,
          text: '이 파일에서 Sheet 탭 정보를 찾지 못했습니다.',
          color: KangColors.slate,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(left: 50, right: 4, bottom: 12),
      padding: const EdgeInsets.all(12),
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
                  maxLines: 1,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
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
            child: Icon(Icons.grid_on_rounded, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              sheetName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KangColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(112, 42),
              padding: const EdgeInsets.symmetric(horizontal: 14),
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
                : const Icon(Icons.download_rounded),
            label: const Text('가져오기'),
            onPressed: importing || disabled ? null : onImport,
          ),
        ],
      ),
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

    return Container(
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
                                      NotificationListener<ScrollNotification>(
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
        ? Tooltip(
            message: value,
            waitDuration: const Duration(milliseconds: 350),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _showCellDetail(label ?? '', value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_full_rounded,
                      size: 13,
                      color: widget.color.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
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
  placeholder,
}
