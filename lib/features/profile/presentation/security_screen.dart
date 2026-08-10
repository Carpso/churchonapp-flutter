import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:church_on_app/core/theme/app_theme.dart';
import '../../admin/data/login_history_service.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _showLoginHistory = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(icon: Icon(Icons.arrow_back, color: scheme.onSurface), onPressed: () => context.pop()),
        title: Text("Security & Privacy", style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section(theme, "Two-Factor Authentication", [
            _buildMenu(
              theme,
              LucideIcons.shield,
              "Setup 2FA",
              "Protect your account with TOTP authentication",
              theme.primaryColor,
              () => context.push('/two-factor-setup'),
            ),
          ]),
          const SizedBox(height: 24),
          _section(theme, "Active Sessions", [
            _buildMenu(
              theme,
              LucideIcons.monitor,
              "Manage Active Sessions",
              "View and manage all your active login sessions",
              scheme.info,
              () => context.push('/active-sessions'),
            ),
          ]),
          const SizedBox(height: 24),
          _section(theme, "Login History", [
            _buildMenu(
              theme,
              LucideIcons.clock,
              _showLoginHistory ? "Hide Login History" : "View Login History",
              "Check your recent sign-in activity",
              scheme.neutral,
              () => setState(() => _showLoginHistory = !_showLoginHistory),
            ),
            if (_showLoginHistory) _buildLoginHistoryList(theme),
          ]),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(title, style: TextStyle(color: theme.primaryColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        ),
        ...children,
      ],
    );
  }

  Widget _buildMenu(ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
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
                  Text(title, style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4), fontSize: 11)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: scheme.onSurface.withValues(alpha: 0.2), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(ThemeData theme, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(text, style: TextStyle(color: color, fontSize: 13)),
    );
  }

  Widget _buildLoginHistoryList(ThemeData theme) {
    final scheme = theme.colorScheme;
    return FutureBuilder<List<LoginRecord>>(
      future: ref.read(loginHistoryServiceProvider).getLoginHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildInfo(theme, "Loading...", scheme.onSurface.withValues(alpha: 0.4));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildInfo(theme, "No login history yet", scheme.onSurface.withValues(alpha: 0.4));
        }
        return Column(
          children: snapshot.data!.map((record) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Icon(
                  record.status == 'success' ? LucideIcons.checkCircle : LucideIcons.xCircle,
                  color: record.status == 'success' ? scheme.success : scheme.error,
                  size: 14,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "${record.ipAddress ?? 'Unknown IP'} • ${_formatDate(record.createdAt)}",
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 11),
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
