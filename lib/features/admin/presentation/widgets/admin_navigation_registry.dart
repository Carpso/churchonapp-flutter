import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AdminTileConfig {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
  final bool Function({required bool isSuperadmin, required bool isPastor, required bool isBishop, required bool isTreasurer}) canAccess;

  const AdminTileConfig({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
    required this.canAccess,
  });
}

class AdminNavigationRegistry {
  static const List<AdminTileConfig> tiles = [
    AdminTileConfig(
      title: "Church Management",
      subtitle: "Members, leadership team, and roles",
      icon: LucideIcons.users,
      color: Color(0xFF6366F1),
      route: "/admin/members",
      canAccess: _isLeadership,
    ),
    AdminTileConfig(
      title: "Giving & Financial Reports",
      subtitle: "Tithes, offerings, payouts & ledger",
      icon: LucideIcons.wallet,
      color: Color(0xFF10B981),
      route: "/admin/giving-reports",
      canAccess: _isFinancialOrLeadership,
    ),
    AdminTileConfig(
      title: "Live Stream Studio",
      subtitle: "Broadcast live services to congregation",
      icon: LucideIcons.video,
      color: Color(0xFFEF4444),
      route: "/admin/live-studio",
      canAccess: _isLeadership,
    ),
    AdminTileConfig(
      title: "Event Scheduler",
      subtitle: "Create events and manage tickets",
      icon: LucideIcons.calendar,
      color: Color(0xFFF59E0B),
      route: "/admin/event-scheduler",
      canAccess: _isLeadership,
    ),
    AdminTileConfig(
      title: "Radio Station Mgmt",
      subtitle: "Stream audio, broadcasts & radio ads",
      icon: LucideIcons.radio,
      color: Color(0xFF8B5CF6),
      route: "/admin/radio-mgmt",
      canAccess: _isLeadership,
    ),
    AdminTileConfig(
      title: "Ad Promotions & Coins",
      subtitle: "Manage COA promo campaigns and ads",
      icon: LucideIcons.coins,
      color: Color(0xFFEC4899),
      route: "/admin/ads",
      canAccess: _isSuperadminOnly,
    ),
     AdminTileConfig(
       title: "Partner Tenants",
       subtitle: "Manage partner stores, cafes & offers",
       icon: LucideIcons.store,
       color: Color(0xFF14B8A6),
       route: "/admin/partners",
       canAccess: _isSuperadminOnly,
     ),
     AdminTileConfig(
       title: "Invite Members",
       subtitle: "Share invite link, QR & quick share options",
       icon: LucideIcons.userPlus,
       color: Color(0xFF3B82F6),
       route: "/invite",
       canAccess: _isLeadership,
     ),
   ];

  static bool _isLeadership({required bool isSuperadmin, required bool isPastor, required bool isBishop, required bool isTreasurer}) {
    return isSuperadmin || isPastor || isBishop;
  }

  static bool _isFinancialOrLeadership({required bool isSuperadmin, required bool isPastor, required bool isBishop, required bool isTreasurer}) {
    return isSuperadmin || isPastor || isBishop || isTreasurer;
  }

  static bool _isSuperadminOnly({required bool isSuperadmin, required bool isPastor, required bool isBishop, required bool isTreasurer}) {
    return isSuperadmin;
  }

  static List<Widget> buildAccessibleTiles(
    BuildContext context, {
    required bool isSuperadmin,
    required bool isPastor,
    required bool isBishop,
    required bool isTreasurer,
  }) {
    final accessible = tiles.where((t) => t.canAccess(
      isSuperadmin: isSuperadmin,
      isPastor: isPastor,
      isBishop: isBishop,
      isTreasurer: isTreasurer,
    )).toList();

    final theme = Theme.of(context);

    return accessible.map((tile) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tile.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(tile.icon, color: tile.color, size: 22),
          ),
          title: Text(tile.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: Text(tile.subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          onTap: () => context.push(tile.route),
        ),
      );
    }).toList();
  }
}
