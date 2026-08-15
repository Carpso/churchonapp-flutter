import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Official Google "G" logo drawn from the brand's 4-path SVG (48x48 viewBox).
/// Rendered with a CustomPainter so no font or asset is required.
class GoogleGLogo extends StatelessWidget {
  final double size;

  const GoogleGLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48.0;
    final matrix = Float64List.fromList([
      s, 0, 0, 0,
      0, s, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);

    void draw(String fill, Path src) {
      canvas.drawPath(
        Path()..addPath(src, Offset.zero, matrix4: matrix),
        Paint()..color = Color(int.parse(fill)),
      );
    }

    // Blue
    draw('0xFF4285F4', Path()
      ..moveTo(48.0, 24.55)
      ..cubicTo(48.0, 22.98, 47.85, 21.46, 47.6, 20.0)
      ..lineTo(24.0, 20.0)
      ..lineTo(24.0, 29.02)
      ..lineTo(36.94, 29.02)
      ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
      ..lineTo(39.89, 42.2)
      ..cubicTo(44.4, 38.02, 48.0, 31.84, 48.0, 24.55)
      ..close());

    // Green
    draw('0xFF34A853', Path()
      ..moveTo(24.0, 48.0)
      ..cubicTo(30.48, 48.0, 35.93, 45.87, 39.89, 42.2)
      ..lineTo(32.16, 36.2)
      ..cubicTo(30.01, 37.65, 27.25, 38.3, 24.0, 38.3)
      ..cubicTo(17.74, 38.3, 12.43, 34.08, 10.53, 28.41)
      ..lineTo(2.55, 34.6)
      ..cubicTo(6.51, 42.62, 14.62, 48.0, 24.0, 48.0)
      ..close());

    // Yellow
    draw('0xFFFBBC05', Path()
      ..moveTo(10.53, 28.41)
      ..cubicTo(10.05, 26.96, 9.77, 25.42, 9.77, 23.82)
      ..cubicTo(9.77, 22.22, 10.05, 21.68, 10.53, 19.23)
      ..lineTo(2.55, 13.04)
      ..cubicTo(0.92, 16.46, 0.0, 20.12, 0.0, 23.82)
      ..cubicTo(0.0, 27.52, 0.92, 31.18, 2.55, 34.6)
      ..lineTo(10.53, 28.41)
      ..close());

    // Red
    draw('0xFFEA4335', Path()
      ..moveTo(24.0, 9.5)
      ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
      ..lineTo(40.05, 6.25)
      ..cubicTo(35.9, 2.38, 30.47, 0.0, 24.0, 0.0)
      ..cubicTo(14.62, 0.0, 6.51, 5.38, 2.55, 13.04)
      ..lineTo(10.53, 19.23)
      ..cubicTo(12.43, 13.56, 17.74, 9.5, 24.0, 9.5)
      ..close());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}