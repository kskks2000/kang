import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/firebase_social_auth.dart';
import '../services/google_calendar_service.dart';
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
        onTap: () => Navigator.of(context)
            .push(
              MaterialPageRoute(builder: (_) => _FeatureScreen(module: module)),
            )
            .then((_) => onRefresh()),
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
        final compact = constraints.maxWidth < 520;
        final dateButton = OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(
            _CalendarDateText.full(date),
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: loading ? null : onPickDate,
        );

        final controls = [
          IconButton.outlined(
            tooltip: '전날',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: loading ? null : onPrevious,
          ),
          if (compact) Expanded(child: dateButton) else dateButton,
          IconButton.outlined(
            tooltip: '다음날',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: loading ? null : onNext,
          ),
          TextButton(
            onPressed: loading ? null : onToday,
            child: const Text('오늘'),
          ),
        ];

        if (compact) {
          return Row(children: controls);
        }

        return Row(
          children: [...controls.take(3), const Spacer(), controls.last],
        );
      },
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

enum _HomeModuleKind { calendar, placeholder }
