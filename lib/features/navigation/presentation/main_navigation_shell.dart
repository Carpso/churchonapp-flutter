import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../connect/data/call_service.dart';

import '../../profile/data/notification_service.dart';
import '../../transport/data/location_tracker_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/presentation/lockdown_overlay.dart';

import 'package:go_router/go_router.dart';

class MainNavigationShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainNavigationShell({
    super.key,
    required this.navigationShell,
  });

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileNotificationServiceProvider).init();
    });
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CallSession?>>(incomingCallStreamProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        final call = next.value!;
        context.push('/call', extra: call);
      }
    });

    // Handle Location Tracking based on Work Mode
    ref.listen<AsyncValue<UserProfile?>>(profileProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        if (next.value!.isWorkMode) {
          ref.read(locationTrackerProvider).startTracking();
        } else {
          ref.read(locationTrackerProvider).stopTracking();
        }
      }
    });

    return LockdownOverlay(
      child: Scaffold(
        body: widget.navigationShell,
        floatingActionButton: FloatingActionButton(
          heroTag: null,
          onPressed: () => _onTap(2),
          backgroundColor: Colors.transparent,
          elevation: 0,
          tooltip: "Carpso Ride",
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.navigationShell.currentIndex == 2 ? const Color(0xFFFFD700) : const Color(0xFF1A1A1A),
              boxShadow: [
                BoxShadow(
                  color: (widget.navigationShell.currentIndex == 2 ? const Color(0xFFFFD700) : Colors.black).withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              LucideIcons.car, 
              color: widget.navigationShell.currentIndex == 2 ? const Color(0xFF1A1A1A) : const Color(0xFFFFD700), 
              size: 30
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          padding: EdgeInsets.zero,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: const Color(0xFFFFFAEB),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, LucideIcons.home, "Home"),
              _buildNavItem(1, LucideIcons.headphones, "Sermons"),
              const SizedBox(width: 48),
              _buildNavItem(3, LucideIcons.users, "Connect"),
              _buildNavItem(4, LucideIcons.user, "Profile"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final bool isActive = widget.navigationShell.currentIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTap(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? Theme.of(context).primaryColor : Colors.grey,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? Theme.of(context).primaryColor : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

