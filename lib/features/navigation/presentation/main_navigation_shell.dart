import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../connect/data/call_service.dart';

import '../../profile/data/notification_service.dart';
import '../../transport/data/location_tracker_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/features/admin/presentation/lockdown_overlay.dart';
import 'package:church_on_app/core/widgets/global_media_player.dart';
import 'package:church_on_app/core/services/session_guard_service.dart';
import 'package:church_on_app/core/services/offline_service.dart';
import 'package:church_on_app/core/services/coins_service.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/features/connect/data/user_activity_service.dart';

import 'package:go_router/go_router.dart';
import 'package:church_on_app/core/utils/responsive.dart';

final navBarVisibleProvider = NotifierProvider<NavBarVisibleNotifier, bool>(
  NavBarVisibleNotifier.new,
);

class NavBarVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void show() => state = true;
  void hide() => state = false;
}

class MainNavigationShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainNavigationShell({super.key, required this.navigationShell});

  @override
  ConsumerState<MainNavigationShell> createState() =>
      _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell>
    with WidgetsBindingObserver {
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileNotificationServiceProvider).init();
      // Activate session guard (remote-config inactivity lockout)
      final timeoutMinutes = widgetRemoteConfig(ref).getInt(
        'session_inactivity_minutes',
        5,
      );
      ref
          .read(sessionGuardProvider)
          .startMonitoring(
            timeout: Duration(minutes: timeoutMinutes),
            onTimeout: _handleSessionTimeout,
          );
      // Activate offline write queue
      ref.read(offlineServiceProvider).startAutoSync();
      // Auto-collect daily coins (cooldown-checked server-side-safe: returns
      // 0 when already collected today, so this is at most once per 20h)
      final coinsSvc = ref.read(coinsServiceProvider);
      coinsSvc.collectDailyCoins().then((earned) {
        if (earned > 0) {
          ref
              .read(userActivityServiceProvider)
              .logActivity(
                type: ActivityType.coinCollected,
                description: 'Daily coin reward',
                coinsEarned: earned,
              );
        }
      }).catchError((e) {
        debugPrint('Daily coin auto-collect failed: $e');
      });
      // Tiered app-open streak bonus (5/10/20/30 by day bucket, once per day)
      final streakCount = ref.read(profileProvider).asData?.value?.streakCount ?? 0;
      coinsSvc.collectAppOpenStreakReward(streakCount).then((earned) {
        if (earned > 0) {
          ref
              .read(userActivityServiceProvider)
              .logActivity(
                type: ActivityType.coinCollected,
                description: 'App-open streak reward',
                coinsEarned: earned,
              );
        }
      }).catchError((e) {
        debugPrint('Streak reward auto-collect failed: $e');
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the app counts as activity — restart the countdown.
    if (state == AppLifecycleState.resumed) {
      ref.read(sessionGuardProvider).registerActivity();
    }
  }

  /// Real session timeout: signs the user out of Supabase, clears
  /// remember-me + tenant context, and redirects to the login screen
  /// (the router redirects automatically when authState.user becomes null).
  Future<void> _handleSessionTimeout() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      ref.read(sessionGuardProvider).unlock();
      return;
    }
    try {
      await ref.read(authProvider.notifier).signOut();
    } catch (e) {
      debugPrint('Session timeout sign-out failed: $e');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your session expired due to inactivity. Please sign in again.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
    ref.read(sessionGuardProvider).unlock();
  }

  void _onTap(int index) {
    ref.read(navBarVisibleProvider.notifier).show();
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CallSession?>>(incomingCallStreamProvider, (
      previous,
      next,
    ) {
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

    final isVisible = ref.watch(navBarVisibleProvider);
    final isWide = MediaQuery.sizeOf(context).width >= Responsive.medium;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (widget.navigationShell.currentIndex != 0) {
          _onTap(0);
          return;
        }
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Press back again to exit Church On App"),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: LockdownOverlay(
        child: Scaffold(
          body: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (!isWide &&
                  notification is ScrollUpdateNotification &&
                  notification.dragDetails != null) {
                final delta = notification.scrollDelta ?? 0;
                if (delta > 0) {
                  ref.read(navBarVisibleProvider.notifier).hide();
                } else if (delta < 0) {
                  ref.read(navBarVisibleProvider.notifier).show();
                }
              }
              return false;
            },
            child: Stack(
              children: [
                if (isWide) _buildWideLayout(context) else widget.navigationShell,
                ValueListenableBuilder<GlobalMediaState>(
                  valueListenable: globalMediaPlayerController.state,
                  builder: (context, mediaState, _) {
                    final bool hasMedia = mediaState.isPlaying || mediaState.title.isNotEmpty;
                    return AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      left: isWide ? 80 : 0,
                      right: 0,
                      bottom: isVisible ? 0 : -80, // Animate out with the nav bar
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: hasMedia ? 1.0 : 0.0,
                        child: hasMedia ? const GlobalMediaPlayer() : const SizedBox.shrink(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          bottomNavigationBar: isWide
              ? null
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  height: isVisible ? 80 + MediaQuery.of(context).padding.bottom : 0,
                  decoration: const BoxDecoration(),
                  clipBehavior: Clip.hardEdge,
                  child: BottomAppBar(
                    padding: EdgeInsets.zero,
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 8,
                    shadowColor: Theme.of(context).shadowColor,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNavItem(0, LucideIcons.home, "Home"),
                        _buildNavItem(1, LucideIcons.headphones, "Sermons"),
                        _buildNavItem(2, LucideIcons.hand, "Give"),
                        _buildNavItem(3, LucideIcons.users, "Connect"),
                        _buildNavItem(4, LucideIcons.user, "Profile"),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// Desktop layout: a NavigationRail on the left + content capped to
  /// [Responsive.maxContentWidth] so wide screens don't stretch full-bleed.
  Widget _buildWideLayout(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentIndex = widget.navigationShell.currentIndex;
    final extended = MediaQuery.sizeOf(context).width >= 1280;

    return ColoredBox(
      color: scheme.surface,
      child: Row(
        children: [
          SafeArea(
            child: NavigationRail(
              extended: extended,
              minExtendedWidth: 200,
              backgroundColor: scheme.surfaceContainerLowest,
              selectedIndex: currentIndex,
              onDestinationSelected: _onTap,
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Center(
                  child: Image.asset(
                    "assets/app_logo.png",
                    width: 36,
                    height: 36,
                    errorBuilder: (c, e, s) => const Icon(Icons.church, size: 32),
                  ),
                ),
              ),
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              destinations: [
                _buildRailDestination(0, LucideIcons.home, "Home"),
                _buildRailDestination(1, LucideIcons.headphones, "Sermons"),
                _buildRailDestination(2, LucideIcons.hand, "Give"),
                _buildRailDestination(3, LucideIcons.users, "Connect"),
                _buildRailDestination(4, LucideIcons.user, "Profile"),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Responsive.maxContentWidth,
                ),
                child: widget.navigationShell,
              ),
            ),
          ),
        ],
      ),
    );
  }

  NavigationRailDestination _buildRailDestination(int index, IconData icon, String label) {
    final theme = Theme.of(context);
    return NavigationRailDestination(
      icon: Icon(icon, size: 22),
      selectedIcon: Icon(icon, size: 22, color: theme.primaryColor),
      label: Text(label),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final bool isActive = widget.navigationShell.currentIndex == index;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    
    return Expanded(
      child: Semantics(
        label: "$label tab",
        button: true,
        selected: isActive,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onTap(index),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? theme.primaryColor.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    icon,
                    color: isActive ? theme.primaryColor : scheme.onSurface.withValues(alpha: 0.4),
                    size: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w900 : FontWeight.w500,
                    color: isActive ? theme.primaryColor : scheme.onSurface.withValues(alpha: 0.4),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
