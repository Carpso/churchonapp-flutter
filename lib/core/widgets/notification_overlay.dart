import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/notification_service.dart';
import 'package:go_router/go_router.dart';

/// In-app notification banner that slides down from the top when a
/// notification arrives while the app is in the foreground.
/// Wraps [child] in a Stack and shows banners above it.
class NotificationOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const NotificationOverlay({super.key, required this.child});

  @override
  ConsumerState<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends ConsumerState<NotificationOverlay> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  OverlayEntry? _currentBanner;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = ref.read(notificationServiceProvider);
      _sub = service.overlayStream.listen(_onNotification);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dismissTimer?.cancel();
    _currentBanner?.remove();
    super.dispose();
  }

  void _onNotification(Map<String, dynamic> data) {
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    if (title.isEmpty && body.isEmpty) return;

    _dismissTimer?.cancel();
    _currentBanner?.remove();

    _currentBanner = OverlayEntry(
      builder: (_) => _NotificationBanner(
        title: title,
        body: body,
        onTap: () {
          _dismissBanner();
          final payload = data['payload'] as String?;
          if (payload != null && payload.isNotEmpty) {
            _handlePayloadNavigation(payload);
          }
        },
        onDismiss: _dismissBanner,
      ),
    );

    Overlay.of(context).insert(_currentBanner!);

    _dismissTimer = Timer(const Duration(seconds: 4), _dismissBanner);
  }

  void _dismissBanner() {
    _dismissTimer?.cancel();
    _currentBanner?.remove();
    _currentBanner = null;
  }

  void _handlePayloadNavigation(String payload) {
    final parts = payload.split(':');
    if (parts.length != 2) return;
    final type = parts[0];
    final id = parts[1];

    if (!mounted) return;
    final router = GoRouter.of(context);
    switch (type) {
      case 'chat':
        router.go('/chat/$id');
        break;
      case 'post':
      case 'prayer':
      case 'testimony':
        router.go('/connect');
        break;
      case 'payment':
        router.go('/wallet');
        break;
      case 'announcement':
        router.go('/');
        break;
      case 'event':
        router.go('/events/$id');
        break;
      case 'klip':
        router.go('/klips/$id');
        break;
      case 'fasting':
      case 'sermon':
        router.go('/');
        break;
      case 'job':
        router.go('/job-notifications');
        break;
      case 'member':
        router.go('/admin/members');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _NotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: GestureDetector(
          onTap: widget.onTap,
          onVerticalDragEnd: (_) => widget.onDismiss(),
          child: Container(
            padding: EdgeInsets.fromLTRB(16, topPadding + 12, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withValues(alpha: 0.85),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Row(
                children: [
                  const Icon(LucideIcons.bell, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.body,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
