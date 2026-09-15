import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Visual helpers shared by the offering-basket manager and the Give tab.
class BasketVisuals {
  BasketVisuals._();

  /// Lucide icons offered when creating/editing a basket. All names are
  /// verified to exist in the pinned `lucide_icons` version.
  static const Map<String, IconData> icons = {
    'hand-heart': LucideIcons.heartHandshake,
    'church': LucideIcons.church,
    'globe': LucideIcons.globe,
    'building-2': LucideIcons.building2,
    'sprout': LucideIcons.sprout,
    'gift': LucideIcons.gift,
    'coins': LucideIcons.coins,
    'landmark': LucideIcons.landmark,
    'sparkles': LucideIcons.sparkles,
    'banknote': LucideIcons.banknote,
    'wallet': LucideIcons.wallet,
    'piggy-bank': LucideIcons.piggyBank,
    'star': LucideIcons.star,
    'sun': LucideIcons.sun,
    'shield': LucideIcons.shield,
  };

  static IconData iconFor(String? name) => icons[name] ?? LucideIcons.heartHandshake;

  /// Standard palette for basket colours.
  static const List<Color> palette = [
    Color(0xFFFFDA03), // sunflower (brand)
    Color(0xFF10B981), // emerald
    Color(0xFF3B82F6), // blue
    Color(0xFF8B5CF6), // violet
    Color(0xFFEF4444), // red
    Color(0xFFF97316), // orange
    Color(0xFF14B8A6), // teal
    Color(0xFFEC4899), // pink
  ];

  static Color colorFor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFFFFDA03);
    var h = hex.replaceFirst('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const Color(0xFFFFDA03) : Color(v);
  }

  static String toHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
