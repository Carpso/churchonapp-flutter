import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/subscription_service.dart';

/// Feature lock wrapper - shows upgrade prompt if user doesn't have access
class FeatureLock extends ConsumerWidget {
  final String featureKey;
  final Widget child;
  final bool showLockIcon;

  const FeatureLock({
    super.key,
    required this.featureKey,
    required this.child,
    this.showLockIcon = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(featureAccessProvider(featureKey));

    return accessAsync.when(
      data: (hasAccess) {
        if (hasAccess) return child;
        return _buildLockedView(context);
      },
      loading: () => child,
      error: (_, __) => child,
    );
  }

  Widget _buildLockedView(BuildContext context) {
    return GestureDetector(
      onTap: () => _showUpgradeSheet(context),
      child: Stack(
        children: [
          Opacity(opacity: 0.3, child: child),
          if (showLockIcon)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.lock, color: Colors.amber, size: 32),
              ),
            ),
        ],
      ),
    );
  }

  void _showUpgradeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UpgradePromptSheet(featureKey: featureKey),
    );
  }
}

class _UpgradePromptSheet extends StatelessWidget {
  final String featureKey;
  const _UpgradePromptSheet({required this.featureKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Icon(LucideIcons.lock, color: Colors.amber, size: 48),
          const SizedBox(height: 16),
          const Text("Premium Feature", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            "Upgrade your subscription to access this feature.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.push('/subscription');
            },
            icon: const Icon(LucideIcons.sparkles, color: Colors.black),
            label: const Text("VIEW PLANS", style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
