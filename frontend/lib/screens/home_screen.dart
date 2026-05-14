import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/firebase_social_auth.dart';
import '../services/google_calendar_service.dart';
import '../services/google_drive_api.dart';
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
        kind: _HomeModuleKind.drive,
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
    if (module.kind == _HomeModuleKind.drive) {
      try {
        await FirebaseSocialAuth.requestGoogleDriveSheetsAccessToken();
      } catch (_) {
        // The Drive screen still shows a retry action and a clear error.
      }
    }

    if (!context.mounted) {
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
    try {
      await FirebaseSocialAuth.requestGoogleCalendarAccessToken();
    } catch (_) {
      // The calendar screen still gives the user a clear retry action.
    }

    if (!context.mounted) {
      return;
    }

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
  });

  final int count;
  final bool loading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.storage_outlined, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'google_drives 저장 데이터',
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

enum _HomeModuleKind { calendar, drive, placeholder }
