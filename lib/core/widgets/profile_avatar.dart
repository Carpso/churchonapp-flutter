import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

/// Shared avatar widget — uses Gravatar (email → MD5), falls back to
/// Facebook-style initials placeholder. Consistent across the entire app.
class ProfileAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? email;
  final String? name;
  final double radius;

  const ProfileAvatar({
    super.key,
    this.avatarUrl,
    this.email,
    this.name,
    this.radius = 24,
  });

  static String gravatarUrl(String email, {int size = 200}) {
    final trimmed = email.trim().toLowerCase();
    final hash = md5.convert(utf8.encode(trimmed)).toString();
    return 'https://www.gravatar.com/avatar/$hash?s=$size&d=404';
  }

  static String initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    String? url = avatarUrl;

    // Fallback 1: Gravatar from email
    if ((url == null || url.isEmpty) && email != null && email!.isNotEmpty) {
      url = gravatarUrl(email!);
    }

    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, __) {},
        child: url == avatarUrl ? null : _Placeholder(name: name, radius: radius),
      );
    }

    return _Placeholder(name: name, radius: radius);
  }
}

class _Placeholder extends StatelessWidget {
  final String? name;
  final double radius;
  const _Placeholder({this.name, required this.radius});

  @override
  Widget build(BuildContext context) {
    final initials = name != null && name!.isNotEmpty
        ? ProfileAvatar.initialsFromName(name!)
        : '?';
    final colors = [
      Colors.blue, Colors.teal, Colors.orange, Colors.purple,
      Colors.red, Colors.green, Colors.indigo, Colors.amber,
    ];
    final color = colors[initials.codeUnits.fold(0, (a, b) => a + b) % colors.length];

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}

/// Extension to get Gravatar URL from any user email.
extension GravatarEmail on String {
  String get gravatar => ProfileAvatar.gravatarUrl(this);
}
