import 'package:flutter/material.dart';
import 'dart:math' as math;

class DietLogo extends StatelessWidget {
  final double size;

  const DietLogo({super.key, this.size = 150});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.2),
            blurRadius: 15,
            spreadRadius: 5,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: CustomPaint(painter: _ForkLeafPainter()),
    );
  }
}

class _ForkLeafPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final w = size.width;
    final h = size.height;

    final Paint forkPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Paint leafPaint = Paint()
      ..color =
          const Color(0xFF4CAF50) // Vibrant Green
      ..style = PaintingStyle.fill;

    // 1. Draw Fork Tines (Top half)
    double tineTop = h * 0.25;
    double tineBottom = h * 0.45;
    double spacing = w * 0.12;

    // Left Tine
    canvas.drawLine(
      Offset(center.dx - spacing, tineTop),
      Offset(center.dx - spacing, tineBottom),
      forkPaint,
    );
    // Middle Tine
    canvas.drawLine(
      Offset(center.dx, tineTop),
      Offset(center.dx, tineBottom),
      forkPaint,
    );
    // Right Tine
    canvas.drawLine(
      Offset(center.dx + spacing, tineTop),
      Offset(center.dx + spacing, tineBottom),
      forkPaint,
    );

    // Fork Base (Connector)
    final Path base = Path();
    base.moveTo(center.dx - spacing, tineBottom);
    base.quadraticBezierTo(
      center.dx,
      tineBottom + (h * 0.1),
      center.dx + spacing,
      tineBottom,
    );
    canvas.drawPath(base, forkPaint..style = PaintingStyle.stroke);

    // 2. Draw Stem (Handle)
    // We draw a curve to look organic
    final Path stem = Path();
    stem.moveTo(center.dx, tineBottom + (h * 0.05));
    stem.quadraticBezierTo(
      center.dx + (w * 0.05),
      h * 0.7,
      center.dx - (w * 0.05),
      h * 0.85,
    );

    Paint stemPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(stem, stemPaint);

    // 3. Draw Leaves
    // Right Leaf
    final Path leafRight = Path();
    leafRight.moveTo(center.dx, h * 0.65);
    leafRight.quadraticBezierTo(
      center.dx + (w * 0.3),
      h * 0.6,
      center.dx + (w * 0.25),
      h * 0.5,
    );
    leafRight.quadraticBezierTo(
      center.dx + (w * 0.1),
      h * 0.55,
      center.dx,
      h * 0.65,
    );
    canvas.drawPath(leafRight, leafPaint);

    // Left Leaf (Smaller)
    final Path leafLeft = Path();
    leafLeft.moveTo(center.dx, h * 0.75);
    leafLeft.quadraticBezierTo(
      center.dx - (w * 0.25),
      h * 0.72,
      center.dx - (w * 0.2),
      h * 0.65,
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
