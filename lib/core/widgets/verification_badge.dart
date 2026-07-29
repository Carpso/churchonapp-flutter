import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class VerificationBadge extends StatelessWidget {
  final double size;
  const VerificationBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Icon(
      LucideIcons.badgeCheck,
      color: Colors.blueAccent,
      size: size,
    );
  }
}
