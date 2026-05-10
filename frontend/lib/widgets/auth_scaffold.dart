import 'package:flutter/material.dart';

import '../theme/kang_theme.dart';
import 'kang_mark.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFCFF), Color(0xFFF8F3FD), Color(0xFFEFFCFA)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: _BackgroundBands()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 40 : 20,
                        vertical: wide ? 34 : 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1060),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Expanded(child: _BrandPanel()),
                                  const SizedBox(width: 54),
                                  SizedBox(width: 434, child: _FormPanel(this)),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _MobileBrandHeader(),
                                  const SizedBox(height: 22),
                                  _FormPanel(this),
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
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const KangMark(size: 66, showWordmark: true),
          const SizedBox(height: 34),
          const _Eyebrow(),
          const SizedBox(height: 14),
          Text(
            'Kang 계정을 위한 프라이빗 허브.',
            style: textTheme.headlineLarge?.copyWith(
              fontSize: 42,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Text(
              '캘린더, 파일, 연락처, 개인 기록을 한 번의 로그인으로 안전하게 연결합니다.',
              style: textTheme.bodyMedium?.copyWith(
                color: KangColors.slate,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 30),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _BrandPill(icon: Icons.verified_user_outlined, label: '회원 계정'),
              _BrandPill(icon: Icons.cloud_done_outlined, label: '연동 준비'),
              _BrandPill(icon: Icons.lock_outline, label: '보안 로그인'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileBrandHeader extends StatelessWidget {
  const _MobileBrandHeader();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [KangMark(size: 48, showWordmark: true), _MiniStatusPill()],
        ),
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel(this.scaffold);

  final AuthScaffold scaffold;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
            boxShadow: [
              BoxShadow(
                color: KangColors.deepPurple.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: KangColors.mintDeep.withValues(alpha: 0.04),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  scaffold.title,
                  style: textTheme.headlineSmall?.copyWith(
                    fontSize: 26,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(scaffold.subtitle, style: textTheme.bodyMedium),
                const SizedBox(height: 24),
                scaffold.child,
              ],
            ),
          ),
        ),
        if (scaffold.footer != null) ...[
          const SizedBox(height: 16),
          scaffold.footer!,
        ],
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MintDash(),
        SizedBox(width: 10),
        Text(
          'KANG PRIVATE HUB',
          style: TextStyle(
            color: KangColors.royalPurple,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _MintDash extends StatelessWidget {
  const _MintDash();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KangColors.mint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const SizedBox(width: 28, height: 4),
    );
  }
}

class _MiniStatusPill extends StatelessWidget {
  const _MiniStatusPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KangColors.mintSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KangColors.mint.withValues(alpha: 0.5)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          'Private',
          style: TextStyle(
            color: KangColors.deepPurple,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _BrandPill extends StatelessWidget {
  const _BrandPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: KangColors.royalPurple, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: KangColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundBands extends StatelessWidget {
  const _BackgroundBands();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BackgroundBandsPainter());
  }
}

class _BackgroundBandsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final purple = Paint()
      ..color = KangColors.royalPurple.withValues(alpha: 0.07);
    final lavender = Paint()
      ..color = KangColors.orchid.withValues(alpha: 0.055);
    final mint = Paint()..color = KangColors.mint.withValues(alpha: 0.16);
    final deep = Paint()
      ..color = KangColors.deepPurple.withValues(alpha: 0.045);

    final topRibbon = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.1)
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.18,
        size.width * 0.46,
        size.height * 0.08,
        0,
        size.height * 0.2,
      )
      ..close();
    canvas.drawPath(topRibbon, purple);

    final mintRibbon = Path()
      ..moveTo(size.width, size.height * 0.08)
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.18,
        size.width * 0.7,
        size.height * 0.42,
        size.width,
        size.height * 0.52,
      )
      ..close();
    canvas.drawPath(mintRibbon, mint);

    final centerWash = Path()
      ..moveTo(0, size.height * 0.43)
      ..cubicTo(
        size.width * 0.2,
        size.height * 0.32,
        size.width * 0.48,
        size.height * 0.42,
        size.width,
        size.height * 0.31,
      )
      ..lineTo(size.width, size.height * 0.38)
      ..cubicTo(
        size.width * 0.62,
        size.height * 0.5,
        size.width * 0.31,
        size.height * 0.43,
        0,
        size.height * 0.56,
      )
      ..close();
    canvas.drawPath(centerWash, lavender);

    final lowerRibbon = Path()
      ..moveTo(0, size.height * 0.88)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.8,
        size.width * 0.58,
        size.height * 0.86,
        size.width,
        size.height * 0.72,
      )
      ..lineTo(size.width, size.height * 0.79)
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.93,
        size.width * 0.32,
        size.height * 0.88,
        0,
        size.height,
      )
      ..close();
    canvas.drawPath(lowerRibbon, deep);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
