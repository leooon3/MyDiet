import 'package:flutter/material.dart';

class DietLogo extends StatelessWidget {
  final double size;
  final bool isDarkBackground;

  const DietLogo({super.key, this.size = 100, this.isDarkBackground = false});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ForkLeafPainter(isDarkBackground),
    );
  }
}

class _ForkLeafPainter extends CustomPainter {
  final bool isDarkBackground;

  _ForkLeafPainter(this.isDarkBackground);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final w = size.width;
    final h = size.height;

    // Adjust colors based on background
    final Color forkColor = isDarkBackground
        ? Colors.white70
        : Colors.grey.shade400;

    final Paint forkPaint = Paint()
      ..color = forkColor
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Paint leafPaint = Paint()
      ..color =
          const Color(0xFF4CAF50) // Vibrant Green
      ..style = PaintingStyle.fill;

    // --- DRAWING LOGIC ---
    double tineTop = h * 0.15;
    double tineBottom = h * 0.40;
    double spacing = w * 0.12;

    // 1. Fork Tines
    canvas.drawLine(
      Offset(center.dx - spacing, tineTop),
      Offset(center.dx - spacing, tineBottom),
      forkPaint,
    );
    canvas.drawLine(
      Offset(center.dx, tineTop),
      Offset(center.dx, tineBottom),
      forkPaint,
    );
    canvas.drawLine(
      Offset(center.dx + spacing, tineTop),
      Offset(center.dx + spacing, tineBottom),
      forkPaint,
    );

    // 2. Base
    final Path base = Path();
    base.moveTo(center.dx - spacing, tineBottom);
    base.quadraticBezierTo(
      center.dx,
      tineBottom + (h * 0.15),
      center.dx + spacing,
      tineBottom,
    );
    canvas.drawPath(base, forkPaint..style = PaintingStyle.stroke);

    // 3. Stem
    final Path stem = Path();
    stem.moveTo(center.dx, tineBottom + (h * 0.08));
    stem.quadraticBezierTo(
      center.dx + (w * 0.05),
      h * 0.7,
      center.dx - (w * 0.05),
      h * 0.9,
    );
    Paint stemPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(stem, stemPaint);

    // 4. Leaves
    final Path leafRight = Path();
    leafRight.moveTo(center.dx, h * 0.65);
    leafRight.quadraticBezierTo(
      center.dx + (w * 0.35),
      h * 0.6,
      center.dx + (w * 0.25),
      h * 0.45,
    );
    leafRight.quadraticBezierTo(
      center.dx + (w * 0.1),
      h * 0.55,
      center.dx,
      h * 0.65,
    );
    canvas.drawPath(leafRight, leafPaint);

    final Path leafLeft = Path();
    leafLeft.moveTo(center.dx, h * 0.75);
    leafLeft.quadraticBezierTo(
      center.dx - (w * 0.3),
      h * 0.72,
      center.dx - (w * 0.25),
      h * 0.62,
    );
    leafLeft.quadraticBezierTo(
      center.dx - (w * 0.1),
      h * 0.68,
      center.dx,
      h * 0.75,
    );
    canvas.drawPath(leafLeft, leafPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
