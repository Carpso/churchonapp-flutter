import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/recommendation_engine_service.dart';
import 'package:church_on_app/core/services/app_update_service.dart';
import 'package:church_on_app/core/services/birthday_service.dart';
import 'package:church_on_app/core/services/smart_prefetch_service.dart';
import 'package:church_on_app/core/services/offline_cache_service.dart';
import 'package:church_on_app/core/widgets/live_stream_indicator.dart';
import 'package:church_on_app/core/widgets/onboarding_quick_start.dart';
import 'package:church_on_app/features/connect/presentation/create_social_post_screen.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_top_bar.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_greeting_header.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_hero_card.dart';
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
import 'package:church_on_app/features/home/presentation/widgets/home_promo_carousel.dart';
import 'package:church_on_app/features/home/presentation/widgets/home_subscription_paywall.dart';
import 'package:church_on_app/features/admin/presentation/widgets/ad_banner_widget.dart';
import '../widgets/announcement_ticker.dart';
import 'package:church_on_app/features/navigation/presentation/carpso_suggestion_card.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/theme/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tenant = ref.watch(currentTenantProvider);
    final isExpired = tenant != null && tenant.isSubscriptionExpired;

    final bottomInset =
        MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight;

    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            ref.invalidate(currentTenantProvider);
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: HomeTopBar(tenant: tenant)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                sliver: isExpired
                    ? SliverToBoxAdapter(
                        child: HomeSubscriptionPaywall(tenant: tenant),
                      )
                    : SliverList(
                        delegate: SliverChildListDelegate([
                          const AnnouncementTicker(),
                          const SizedBox(height: 16),
                          const LiveStreamIndicator(),
                          const SizedBox(height: 20),
                          const HomeGreetingHeader(),
                          const SizedBox(height: 20),
                          const HomeStreakPreview(),
                          const SizedBox(height: 8),
                          const CarpsoSuggestionCard(contextType: 'home'),
                          const SizedBox(height: 20),
                          const OnboardingQuickStart(),
                          const SizedBox(height: 20),
                          const RecommendationCarouselWidget(),
                          const SizedBox(height: 20),
                          const HomeDailyVerse(),
                          const SizedBox(height: 20),
                          if (tenant == null) const HomeSmartReminder(),
                          const SizedBox(height: 20),
                          const HomeHeroCard(),
                          const SizedBox(height: 30),

                          // Collapsible Admin & Promo Section
                          _buildAdminPromoSection(tenant),

                          const HomeQuickActions(),
                          const SizedBox(height: 30),
                          const HomeSectionTitle(title: "Sparkle Picks"),
                          const HomeSparkleGrid(),
                          const SizedBox(height: 30),
                          const HomeLatestSermon(),
                          const SizedBox(height: 30),
                          const HomeEventTimeline(),
                          const SizedBox(height: 30),
                          const HomeSectionTitle(title: "News"),
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
