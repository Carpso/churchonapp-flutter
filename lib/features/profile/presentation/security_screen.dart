import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../admin/data/login_history_service.dart';
import '../../auth/presentation/two_factor_setup_screen.dart';
import 'active_sessions_screen.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _showLoginHistory = false;

  @override
  Widget build(BuildContext context) {
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
            _buildMenu(
              LucideIcons.monitor,
              "Manage Active Sessions",
              "View and manage all your active login sessions",
              Colors.blueAccent,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActiveSessionsScreen()),
              ),
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
