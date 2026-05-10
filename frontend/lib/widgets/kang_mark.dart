import 'package:flutter/material.dart';

import '../theme/kang_theme.dart';

class KangMark extends StatelessWidget {
  const KangMark({
    super.key,
    this.size = 64,
    this.showWordmark = false,
    this.compact = false,
  });

  final double size;
  final bool showWordmark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _KangMarkPainter()),
    );

    if (!showWordmark) {
      return mark;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: compact ? 10 : 14),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kang',
              style: TextStyle(
                color: compact ? Colors.white : KangColors.ink,
                fontSize: compact ? 21 : 27,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            Text(
              'Private Hub',
              style: TextStyle(
                color: compact ? Colors.white70 : KangColors.slate,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KangMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.width * 0.2;
    final background = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          KangColors.deepPurple,
          KangColors.royalPurple,
          KangColors.orchid,
        ],
      ).createShader(rect);
    canvas.drawRRect(background, bgPaint);

    final sheenPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.035;
    canvas.drawRRect(background.deflate(size.width * 0.07), sheenPaint);

    final mintPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), KangColors.mint],
      ).createShader(rect);

    final stem = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.29,
        size.height * 0.22,
        size.width * 0.13,
        size.height * 0.56,
      ),
      Radius.circular(size.width * 0.055),
    );
    canvas.drawRRect(stem, mintPaint);

    final upper = Path()
      ..moveTo(size.width * 0.45, size.height * 0.49)
      ..lineTo(size.width * 0.66, size.height * 0.22)
      ..lineTo(size.width * 0.81, size.height * 0.22)
      ..lineTo(size.width * 0.58, size.height * 0.53)
      ..close();
    canvas.drawPath(upper, mintPaint);

    final lower = Path()
      ..moveTo(size.width * 0.48, size.height * 0.51)
      ..lineTo(size.width * 0.62, size.height * 0.46)
      ..lineTo(size.width * 0.82, size.height * 0.78)
      ..lineTo(size.width * 0.66, size.height * 0.78)
      ..close();
    canvas.drawPath(lower, mintPaint);

    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.29),
      size.width * 0.025,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
