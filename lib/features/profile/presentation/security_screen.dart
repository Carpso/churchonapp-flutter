import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../admin/data/session_service.dart';
import '../../admin/data/login_history_service.dart';
import '../../auth/presentation/two_factor_setup_screen.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _showLoginHistory = false;

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(activeSessionsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("Security & Privacy", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section("Two-Factor Authentication", [
            _buildMenu(
              LucideIcons.shield,
              "Setup 2FA",
              "Protect your account with TOTP authentication",
              Colors.amber,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TwoFactorSetupScreen())),
            ),
          ]),
          const SizedBox(height: 24),
          _section("Active Sessions", [
            ...sessionsAsync.when(
              data: (sessions) {
                final active = sessions.where((s) => s.isActive).toList();
                if (active.isEmpty) {
                  return [
                    _buildInfo("No active sessions found", Colors.white38),
                  ];
                }
                return active.map((s) => _buildSessionTile(s)).toList();
              },
              loading: () => [_buildInfo("Loading sessions...", Colors.white38)],
              error: (e, _) => [_buildInfo("Error: $e", Colors.red)],
            ),
            const SizedBox(height: 10),
            _buildMenu(
              LucideIcons.logOut,
              "Logout All Devices",
              "Sign out from all active sessions",
              Colors.red,
              () => _confirmLogoutAll(),
            ),
          ]),
          const SizedBox(height: 24),
          _section("Login History", [
            _buildMenu(
              LucideIcons.clock,
              _showLoginHistory ? "Hide Login History" : "View Login History",
              "Recent login attempts on your account",
              Colors.blueGrey,
              () => setState(() => _showLoginHistory = !_showLoginHistory),
            ),
            if (_showLoginHistory) _buildLoginHistoryList(),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(title, style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        ),
        ...children,
      ],
    );
  }

  Widget _buildMenu(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(text, style: TextStyle(color: color, fontSize: 13)),
    );
  }

  Widget _buildSessionTile(UserSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: session.isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              session.isActive ? LucideIcons.wifi : LucideIcons.wifiOff,
              color: session.isActive ? Colors.green : Colors.grey,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.deviceInfo ?? "Unknown Device", style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text("${session.ipAddress ?? 'Unknown IP'} • ${_formatDate(session.lastActiveAt)}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginHistoryList() {
    return FutureBuilder<List<LoginRecord>>(
      future: ref.read(loginHistoryServiceProvider).getLoginHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildInfo("Loading...", Colors.white38);
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildInfo("No login history yet", Colors.white38);
        }
        return Column(
          children: snapshot.data!.map((record) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Icon(
                  record.status == 'success' ? LucideIcons.checkCircle : LucideIcons.xCircle,
                  color: record.status == 'success' ? Colors.green : Colors.red,
                  size: 14,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "${record.ipAddress ?? 'Unknown IP'} • ${_formatDate(record.createdAt)}",
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
          )).toList(),
        );
      },
    );
  }

  void _confirmLogoutAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text("Logout All Devices?", style: TextStyle(color: Colors.white)),
        content: const Text("This will sign you out from all other active sessions.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(sessionServiceProvider).logoutAllSessions();
              ref.invalidate(activeSessionsProvider);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Logged out all other devices ✅"), backgroundColor: Colors.green),
                );
              }
            },
            child: const Text("LOGOUT ALL", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
