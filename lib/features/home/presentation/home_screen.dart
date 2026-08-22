import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/i18n/l10n.dart';
import 'package:church_on_app/core/services/recommendation_engine_service.dart';
import 'package:church_on_app/core/services/app_update_service.dart';
import 'package:church_on_app/core/services/birthday_service.dart';
import 'package:church_on_app/core/services/smart_prefetch_service.dart';
import 'package:church_on_app/core/services/offline_cache_service.dart';
import 'package:church_on_app/core/widgets/live_stream_indicator.dart';
import 'package:church_on_app/core/widgets/feature_lock.dart';
import 'package:church_on_app/core/widgets/global_media_player.dart';
import 'package:church_on_app/core/widgets/onboarding_quick_start.dart';
import 'package:church_on_app/features/connect/presentation/create_social_post_screen.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_top_bar.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_greeting_header.dart';

import 'package:church_on_app/features/home/presentation/widgets/home_quick_actions.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_sparkle_grid.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_latest_sermon.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_event_timeline.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_news.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_daily_verse.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_section_title.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_streak_preview.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_smart_reminder.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_admin_dashboard.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_hero_carousel.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_promo_carousel.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_subscription_paywall.dart';
import 'package:church_on_app/features/admin/presentation/special_offer_manager_screen.dart';
import 'package:church_on_app/features/admin/presentation/widgets/ad_banner_widget.dart';
import '../widgets/announcement_ticker.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:church_on_app/core/utils/responsive.dart';

final unreadCountProvider = StreamProvider.autoDispose<int>((ref) {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return Stream.value(0);

  return supabase
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)
      .map((rows) => rows.where((r) => r['is_read'] == false).length);
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  bool _showAdminPromo = false;

  final ScrollController _scrollCtrl = ScrollController();

  final Map<String, GlobalKey> _sectionKeys = {
    'actions': GlobalKey(),
    'sparkle': GlobalKey(),
    'sermons': GlobalKey(),
    'events': GlobalKey(),
    'recommended': GlobalKey(),
    'news': GlobalKey(),
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showWelcomeOverlay();
      _initPostAuthServices();
    });
  }

  Future<void> _initPostAuthServices() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (!mounted) return;

    // Check for app updates (non-blocking)
    unawaited(AppUpdateService.checkForUpdate(context, isInForeground: false));

    // Birthday celebration check
    unawaited(BirthdayService.checkAndShow(context, ref));

    // Prefetch data for offline resilience
    final tenant = ref.read(currentTenantProvider);
    final smartPrefetch = ref.read(smartPrefetchProvider);
    unawaited(smartPrefetch.prefetchAll(tenantId: tenant?.id));

    // Cache critical data for offline access
    final cacheService = OfflineCacheService();
    final criticalCache = CriticalDataCache(
      cacheService,
      Supabase.instance.client,
    );
    unawaited(criticalCache.cacheAllCriticalData());
  }

  Future<void> _showWelcomeOverlay() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool('coach_home_welcome') ?? false;
    if (hasSeen || !mounted) return;
    await prefs.setBool('coach_home_welcome', true);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(
              LucideIcons.sparkles,
              color: Theme.of(context).colorScheme.warning,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              "Welcome!",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _guideItem(
              LucideIcons.send,
              "Give",
              "Tap GIVE in your wallet to tithe or offer securely",
            ),
            _guideItem(
              LucideIcons.coins,
              "Church Coins",
              "Earn free coins daily or buy with Mobile Money",
            ),
            _guideItem(
              LucideIcons.badgePercent,
              "Redeem",
              "Spend coins at partner bookshops & coffee shops",
            ),
            _guideItem(
              LucideIcons.gamepad2,
              "Bible Quiz",
              "Test your knowledge and win coins",
            ),
            _guideItem(
              LucideIcons.users,
              "Connect",
              "Share testimonies and join prayer requests",
            ),
            const SizedBox(height: 12),
            Text(
              "Find help anytime from Profile > Support & Guides",
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "GET STARTED",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.warning,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminPromoSection(Tenant? tenant) {
    final profile = ref.watch(profileProvider).value;
    final bool isAdmin = profile?.isAdminOrHigher ?? false;
    final bool isOwnerTeam = profile?.role == 'superadmin' ||
        profile?.role == 'coa_employee' ||
        profile?.role == 'employee';

    return Column(
      children: [
        if (isAdmin) ...[
          GestureDetector(
            onTap: () => setState(() => _showAdminPromo = !_showAdminPromo),
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.shieldCheck,
                    size: 18,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "ADMIN & PROMOTIONS",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Icon(
                    _showAdminPromo
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showAdminPromo) ...[
            const HomeAdminDashboard(),
            const SizedBox(height: 30),
            if (isOwnerTeam) ...[
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SpecialOfferManagerScreen(),
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.tag,
                        size: 18,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "MANAGE SPECIAL OFFERS",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const HomePromoCarousel(),
            const SizedBox(height: 16),
            const AdBannerWidget(placement: 'home'),
            const SizedBox(height: 30),
          ],
        ],
        if (!isAdmin) ...[
          const HomePromoCarousel(),
          const SizedBox(height: 16),
          const AdBannerWidget(placement: 'home'),
          const SizedBox(height: 30),
        ],
      ],
    );
  }

  void _scrollToSection(String id) {
    final ctx = _sectionKeys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.08,
      );
      return;
    }
    // SliverList children are built lazily — sections far below the viewport
    // have no BuildContext yet, so the old tap silently did nothing. Jump
    // proportionally into the section's region, then reveal once built.
    unawaited(_jumpToLazySection(id));
  }

  Future<void> _jumpToLazySection(String id) async {
    const order = [
      'actions',
      'sparkle',
      'sermons',
      'events',
      'recommended',
      'news',
    ];
    final idx = order.indexOf(id);
    if (idx < 0) return;
    final controller = _scrollCtrl;
    if (!controller.hasClients) return;
    await controller.animateTo(
      controller.position.maxScrollExtent * (idx + 1) / (order.length + 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
    final retryCtx = _sectionKeys[id]?.currentContext;
    if (!mounted || retryCtx == null) return;
    // retryCtx comes from a GlobalKey (not State.context) — safe across the
    // scroll-animation await; lint can't see that.
    Scrollable.ensureVisible(
      // ignore: use_build_context_synchronously
      retryCtx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  Widget _buildQuickJumpBar() {
    final items = <(String, IconData, String)>[
      ('actions', LucideIcons.zap, context.tr('Quick Actions')),
      ('sparkle', LucideIcons.sparkles, 'Picks'),
      ('sermons', LucideIcons.mic2, context.tr('Sermons')),
      ('events', LucideIcons.calendar, context.tr('Events')),
      ('recommended', LucideIcons.thumbsUp, 'For You'),
      ('news', LucideIcons.newspaper, 'News'),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (id, icon, label) = items[i];
          return GestureDetector(
            onTap: () => _scrollToSection(id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 13,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContinueListening() {
    return ValueListenableBuilder<GlobalMediaState>(
      valueListenable: globalMediaPlayerController.state,
      builder: (context, m, _) {
        if (m.title.isEmpty) return const SizedBox.shrink();
        final progress = m.duration.inMilliseconds == 0
            ? 0.0
            : (m.position.inMilliseconds / m.duration.inMilliseconds).clamp(
                0.0,
                1.0,
              );
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFDA03),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.music,
                      color: Colors.black,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "NOW PLAYING",
                          style: TextStyle(
                            color: Color(0xFFFFDA03),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (m.subtitle.isNotEmpty)
                          Text(
                            m.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        globalMediaPlayerController.skipBackward(),
                    icon: const Icon(
                      LucideIcons.skipBack,
                      color: Colors.white70,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  GestureDetector(
                    onTap: () => globalMediaPlayerController.togglePlayPause(),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFDA03),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        m.isPlaying
                            ? LucideIcons.pause
                            : LucideIcons.play,
                        color: Colors.black,
                        size: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        globalMediaPlayerController.skipForward(),
                    icon: const Icon(
                      LucideIcons.skipForward,
                      color: Colors.white70,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.toDouble(),
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(
                    Color(0xFFFFDA03),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tenant = ref.watch(currentTenantProvider);
    final isExpired = tenant != null && tenant.isSubscriptionExpired;

    final bottomInset =
        MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight;
    final hPad = Responsive.hPadding(context);

    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            // In-place tenant reload — invalidating currentTenantProvider
            // resets state to null, which makes the router redirect to
            // /select-church while the home tab is being refreshed.
            await ref.read(currentTenantProvider.notifier).reload();
            await Future.delayed(const Duration(milliseconds: 300));
          },
          child: CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              SliverToBoxAdapter(child: HomeTopBar(tenant: tenant)),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                sliver: isExpired
                    ? SliverToBoxAdapter(
                        child: HomeSubscriptionPaywall(tenant: tenant),
                      )
                    : SliverList(
                        delegate: SliverChildListDelegate([
                          _buildQuickJumpBar(),
                          const SizedBox(height: 16),
                          const AnnouncementTicker(),
                          const SizedBox(height: 16),
                          FeatureLock(
                            featureKey: 'live_streaming',
                            showLockIcon: false,
                            child: const LiveStreamIndicator(),
                          ),
                          const SizedBox(height: 20),
                          const HomeGreetingHeader(),
                          const SizedBox(height: 16),
                          _buildContinueListening(),
                          const SizedBox(height: 20),
                          const HomeDailyVerse(),
                          const SizedBox(height: 20),
                          const HomeHeroCarousel(),
                          const SizedBox(height: 20),
                          const HomeStreakPreview(),
                          const SizedBox(height: 20),
                          const OnboardingQuickStart(),
                          const SizedBox(height: 20),
                          if (tenant == null) const HomeSmartReminder(),
                          const SizedBox(height: 20),

                          Padding(
                            key: _sectionKeys['actions'],
                            padding: EdgeInsets.zero,
                            child: const HomeQuickActions(),
                          ),
                          const SizedBox(height: 30),

                          // Service priority per user feedback: latest sermon
                          // + events sit directly under quick actions.
                          Padding(
                            key: _sectionKeys['sermons'],
                            padding: EdgeInsets.zero,
                            child: const HomeLatestSermon(),
                          ),
                          const SizedBox(height: 30),
                          Padding(
                            key: _sectionKeys['events'],
                            padding: EdgeInsets.zero,
                            child: const HomeEventTimeline(),
                          ),
                          const SizedBox(height: 30),

                          // Collapsible Admin & Promo Section (Special Offer)
                          _buildAdminPromoSection(tenant),

                          Padding(
                            key: _sectionKeys['sparkle'],
                            padding: EdgeInsets.zero,
                            child: const HomeSectionTitle(
                              title: "Sparkle Picks",
                            ),
                          ),
                          const HomeSparkleGrid(),
                          const SizedBox(height: 30),
                          Padding(
                            key: _sectionKeys['recommended'],
                            padding: EdgeInsets.zero,
                            child: const RecommendationCarouselWidget(),
                          ),
                          const SizedBox(height: 30),
                          Padding(
                            key: _sectionKeys['news'],
                            padding: EdgeInsets.zero,
                            child: const HomeSectionTitle(title: "News"),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 10,
                              bottom: 15,
                            ),
                            child: Text(
                              "Disclaimer: Church On App is not affiliated with any news providers. All content belongs to respective owners.",
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.4),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          const HomeNews(),
                          SizedBox(height: 80 + bottomInset),
                        ]),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: 'Create new post',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CreateSocialPostScreen(),
          ),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        child: Icon(
          LucideIcons.plus,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}
