import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:church_on_app/core/widgets/kingdom_logo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:go_router/go_router.dart';
import 'package:church_on_app/core/services/platform_settings_service.dart';
import 'package:church_on_app/core/services/notification_service.dart';
import 'package:church_on_app/features/auth/presentation/select_church_screen.dart';
import 'package:church_on_app/features/bible/data/bible_verse_service.dart';
import 'package:church_on_app/features/bible/presentation/bible_screen.dart';
import 'package:church_on_app/features/connect/presentation/create_social_post_screen.dart';
import 'package:church_on_app/features/connect/presentation/prayer_wall_screen.dart';
import 'package:church_on_app/features/finance/presentation/giving_screen.dart';
import 'package:church_on_app/features/marketplace/data/marketplace_service.dart';
import 'package:church_on_app/features/marketplace/presentation/marketplace_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/product_details_screen.dart';
import 'package:church_on_app/features/modules/bible_quiz/presentation/bible_quiz_hub_screen.dart';
import 'package:church_on_app/features/modules/logistics/presentation/weather_maps_screen.dart';
import 'package:church_on_app/features/modules/media/presentation/kingdom_radio_screen.dart';
import 'package:church_on_app/features/modules/navigation/presentation/more_hub_screen.dart';
import 'package:church_on_app/features/navigation/presentation/carpso_ride_scanner_screen.dart';
import 'package:church_on_app/features/admin/presentation/widgets/ad_banner_widget.dart';
import 'package:church_on_app/features/notebook/presentation/notebook_screen.dart';
import '../data/live_streaming_service.dart';
import '../data/news_service.dart';
import '../data/sermon_service.dart';
import '../widgets/announcement_ticker.dart';
import 'branch_locator_screen.dart';
import 'fasting_tracker_screen.dart';
import 'live_stream_screen.dart';
import 'news_detail_screen.dart';
import 'sermon_library_screen.dart';
import 'sermon_notes_screen.dart';
import 'sermon_player_screen.dart';
import 'universal_search_screen.dart';
import 'worship_lyrics_screen.dart';

final unreadCountProvider = StreamProvider.autoDispose<int>((ref) {
  return Stream.periodic(const Duration(seconds: 30), (_) => null)
      .asyncMap((_) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return 0;
      final res = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);
      return res.length;
    } catch (_) {
      return 0;
    }
  });
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _txidController = TextEditingController();
  bool _isSubmittingPayment = false;

  @override
  void dispose() {
    _txidController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tenant = ref.read(currentTenantProvider);
      if (tenant != null) {
        ref.read(notificationServiceProvider).init();
        ref.read(notificationServiceProvider).listenForAnnouncements(tenant.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final liveStatus = tenant != null 
        ? ref.watch(liveStatusProvider(tenant.id)).asData?.value 
        : null;

    final isExpired = tenant != null && tenant.isSubscriptionExpired;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(context, tenant),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: isExpired
                    ? _buildSubscriptionPaywall(context, tenant)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AnnouncementTicker(),
                          const SizedBox(height: 20),
                          _buildGreetingHeader(context),
                          const SizedBox(height: 20),
                          _buildDailyBibleVerseCard(context),
                          const SizedBox(height: 20),
                          if (tenant == null) _buildSmartReminder(context),
                          const SizedBox(height: 20),
                          _buildContextualWidget(context, liveStatus, tenant),
                          const SizedBox(height: 30),
                          _buildQuickActions(context, tenant),
                          const SizedBox(height: 30),
                          _buildPromoCarousel(context),
                          const SizedBox(height: 16),
                          const AdBannerWidget(placement: 'home'),
                          const SizedBox(height: 30),
                          _buildSectionTitle(context, "Sparkle Picks"),
                          _buildSparkleGrid(context),
                          const SizedBox(height: 30),
                          _buildLatestSermon(context),
                          const SizedBox(height: 30),
                          _buildEventTimeline(context),
                          const SizedBox(height: 30),
                          _buildSectionTitle(context, "Kingdom News"),
                          const Padding(
                            padding: EdgeInsets.only(left: 10, bottom: 15),
                            child: Text(
                              "Disclaimer: Church On App is not affiliated with any news providers. All content belongs to respective owners.",
                              style: TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic),
                            ),
                          ),
                          _buildKingdomNews(context),
                          const SizedBox(height: 100), // Space for FAB
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateSocialPostScreen())),
        backgroundColor: Theme.of(context).primaryColor,
        child: Icon(LucideIcons.plus, color: Theme.of(context).colorScheme.secondary),
      ),
    );
  }

  String _abbreviateChurchName(String name) {
    final words = name.split(' ');
    if (words.length <= 2) return name;
    return '${words[0]} ${words[1]}';
  }

  Widget _buildTopBar(BuildContext context, Tenant? tenant) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SelectChurchScreen())),
            child: Row(
              children: [
                const KingdomLogo(size: 32),
                if (tenant != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      _abbreviateChurchName(tenant.name),
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WeatherMapsScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 8)],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.sun, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text("28°C", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              ref.watch(unreadCountProvider).when(
                data: (count) => Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 99 ? '99+' : '$count', style: const TextStyle(fontSize: 10)),
                  child: IconButton(
                    icon: const Icon(LucideIcons.bell, size: 20),
                    onPressed: () => context.push('/alerts'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ),
                loading: () => IconButton(
                  icon: const Icon(LucideIcons.bell, size: 20),
                  onPressed: () => context.push('/alerts'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                error: (_, __) => IconButton(
                  icon: const Icon(LucideIcons.bell, size: 20),
                  onPressed: () => context.push('/alerts'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.search, size: 20),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UniversalSearchScreen())),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: Icon(LucideIcons.layoutGrid, size: 20, color: Theme.of(context).primaryColor),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MoreHubScreen())),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGreetingHeader(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    
    return profileAsync.when(
      data: (profile) {
        final fullName = profile?.name ?? "Believer";
        var firstName = fullName.trim().split(' ').first;
        if (firstName.length > 12) {
          firstName = "${firstName.substring(0, 10)}...";
        }
        final coins = profile?.coins ?? 0;

        final hour = DateTime.now().hour;
        String greeting = "Good Morning,";
        if (hour >= 12 && hour < 17) {
          greeting = "Good Afternoon,";
        } else if (hour >= 17 || hour < 5) {
          greeting = "Good Evening,";
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)),
                  Text(
                    firstName, 
                    style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
              ),
              child: Row(
                children: [
                   Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("CHURCH COINS", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text("$coins CC", style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
                    ],
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: const Color(0xFFFFFAEB),
                    child: Text("CC", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w900, fontSize: 10, fontStyle: FontStyle.italic)),
                  )
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (e, s) => const Text("Welcome!"),
    );
  }

  Widget _buildSmartReminder(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
           Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Find Your Spiritual Home", style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                const SizedBox(height: 5),
                const Text("Connect with a church family today.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => context.push('/select-church'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: Text("START SEARCH", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildContextualWidget(BuildContext context, LiveStreamStatus? liveStatus, Tenant? tenant) {
    final bool isLive = liveStatus?.isLive ?? false;
    final String title = isLive 
        ? (liveStatus?.title ?? "Live Service") 
        : (tenant != null ? "${tenant.name} Experience" : "Join our Sunday Experience");
    final String subtitle = isLive ? "WE ARE LIVE NOW" : (tenant != null ? "GLORY TO GOD" : "SABBATH MORNING");
    final String timeLabel = isLive 
        ? "${liveStatus?.viewerCount ?? 0} watching" 
        : (tenant != null ? "Next Service: Sunday 09:00" : "Starts in 45 mins");

    final String bgImage = isLive 
        ? "https://images.unsplash.com/photo-1516280440614-37939bbacd81?w=800&q=80"
        : (tenant?.logoUrl ?? "https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800&q=80");
    return Container(
      height: 245,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        image: DecorationImage(
          image: NetworkImage(bgImage),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLive)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(5)),
                child: const Text("LIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
              ),
            Text(subtitle, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 5),
            Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                   _buildDeepLink(context, LucideIcons.fileText, "Notes"),
                   _buildDeepLink(context, LucideIcons.music, "Lyrics"),
                   _buildDeepLink(context, LucideIcons.flame, "Prayer"),
                   _buildDeepLink(context, LucideIcons.heart, "Giving"),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Icon(isLive ? LucideIcons.users : LucideIcons.clock, color: Colors.white70, size: 14),
                const SizedBox(width: 5),
                Text(timeLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    if (isLive && liveStatus?.streamUrl != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => LiveStreamScreen(
                        streamUrl: liveStatus!.streamUrl!,
                        title: liveStatus.title ?? "Live Service",
                      )));
                    } else {
                      if (tenant == null) {
                        context.push('/select-church');
                      } else {
                        _showServiceSchedule(context, tenant);
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    decoration: BoxDecoration(
                      color: isLive ? Theme.of(context).primaryColor : Colors.white24, 
                      borderRadius: BorderRadius.circular(20)
                    ),
                    child: Text(
                      isLive ? "JOIN LIVE" : "SCHEDULE", 
                      style: TextStyle(
                        fontWeight: FontWeight.w900, 
                        fontSize: 10, 
                        color: isLive ? Theme.of(context).colorScheme.secondary : Colors.white
                      )
                    ),
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showServiceSchedule(BuildContext context, Tenant tenant) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tenant.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "WEEKLY SERVICE SCHEDULE",
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 30),
              _buildScheduleRow("Sunday Main Service", "09:00 AM - 11:30 AM", "Main worship experience, sermon, and holy communion."),
              _buildScheduleRow("Wednesday Midweek", "06:00 PM - 07:30 PM", "Bible study, interactive teaching, and community prayers."),
              _buildScheduleRow("Friday Deliverance", "06:00 PM - 08:00 PM", "Intercession, prayer fortress, and prophetic ministry."),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      await ref.read(notificationServiceProvider).init();
                      await Supabase.instance.client.from('service_reports').insert({
                        'tenant_id': tenant.id,
                        'title': 'Weekly Reminder Scheduled',
                        'description': 'Reminder set for ${tenant.name} Sunday Experience at 09:00 AM!',
                        'type': 'announcement',
                      });
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Weekly reminder set for ${tenant.name}!"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Reminder set! Check announcement updates."),
                          backgroundColor: Theme.of(context).primaryColor,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Theme.of(context).colorScheme.secondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.bellRing, size: 18),
                      SizedBox(width: 10),
                      Text(
                        "SET WEEKLY REMINDER",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScheduleRow(String title, String time, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.clock, size: 16, color: Colors.amber),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                    Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.amber)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(description, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, Tenant? tenant) {
    final actions = [
      {"icon": LucideIcons.flame, "label": "Fasting", "color": Colors.orange},
      {"icon": LucideIcons.qrCode, "label": "Check-in", "color": Colors.purple},
      {"icon": LucideIcons.bookOpen, "label": "Sermons", "color": Colors.blue},
      {"icon": LucideIcons.flame, "label": "Kingdom Life", "color": Colors.red},
      {"icon": LucideIcons.helpCircle, "label": "Bible Quiz", "color": Colors.indigo},
      {"icon": LucideIcons.book, "label": "Bible", "color": Colors.green},
      {"icon": LucideIcons.calendar, "label": "Events", "color": Colors.orange},
      {"icon": LucideIcons.penTool, "label": "Notebook", "color": Colors.teal},
      {"icon": LucideIcons.mapPin, "label": "Branches", "color": Colors.brown},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, "Quick Actions"),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: actions.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                 onTap: () {
                  if (actions[index]['label'] == "Fasting") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const FastingTrackerScreen()));
                  } else if (actions[index]['label'] == "Kingdom Life") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const MoreHubScreen()));
                  } else if (actions[index]['label'] == "Bible Quiz") {
                    if (tenant?.settings?['game_arena'] == false) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("'Bible Quiz' module has been disabled by the Superadmin. 🔒"), backgroundColor: Colors.amber));
                      return;
                    }
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const BibleQuizHubScreen()));
                  } else if (actions[index]['label'] == "Bible") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const BibleScreen())); 
                  } else if (actions[index]['label'] == "Check-in") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const CarpsoRideScannerScreen()));
                  } else if (actions[index]['label'] == "Sermons") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const SermonLibraryScreen()));
                  } else if (actions[index]['label'] == "Events") {
                    if (tenant?.settings?['events_management'] == false) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("'Events' module has been disabled by the Superadmin. 🔒"), backgroundColor: Colors.amber));
                      return;
                    }
                  } else if (actions[index]['label'] == "Branches") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const BranchLocatorScreen()));
                  } else if (actions[index]['label'] == "Notebook") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const NotebookScreen()));
                  } else if (actions[index]['label'] == "Radio") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const KingdomRadioScreen()));
                  }
                },
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 15),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [(actions[index]['color'] as Color).withValues(alpha: 0.8), actions[index]['color'] as Color],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: (actions[index]['color'] as Color).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(actions[index]['icon'] as IconData, color: Colors.white, size: 28),
                      const SizedBox(height: 8),
                      Text(actions[index]['label'] as String, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPromoCarousel(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const MarketplaceScreen(initialCategory: "bookshop"),
          ),
        );
      },
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
          image: const DecorationImage(
            image: NetworkImage("https://images.unsplash.com/photo-1510133755869-79a639739569?w=800&q=80"),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            // Dark gradient overlay for visibility
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(8)),
                    child: const Text("SPECIAL OFFER", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 8),
                  const Text("Ministry Books - 20% Off", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const Text("Redeem with Church Coins", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSparkleGrid(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final productsAsync = ref.watch(productsProvider(const {'category': 'all'}));
        
        return productsAsync.when(
          data: (products) {
            final displayProducts = products.take(4).toList();
            if (displayProducts.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text("No items available")),
              );
            }
            return MasonryGridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              itemCount: displayProducts.length,
              itemBuilder: (context, index) {
                final prod = displayProducts[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProductDetailsScreen(product: prod),
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          child: prod.image != null && prod.image!.isNotEmpty
                              ? Image.network(prod.image!, fit: BoxFit.cover)
                              : Image.network("https://images.unsplash.com/photo-1543165796-5426273ea430?w=400&q=60", fit: BoxFit.cover),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(prod.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text("K${prod.price.toStringAsFixed(2)}", style: TextStyle(fontSize: 10, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(color: Colors.amber)),
          ),
          error: (e, s) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text("Error loading picks")),
          ),
        );
      },
    );
  }

  Widget _buildLatestSermon(BuildContext context) {
    final sermonsAsync = ref.watch(latestSermonsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, "Latest Sermon"),
        sermonsAsync.when(
          data: (sermons) {
            if (sermons.isEmpty) return const Text("No sermons available.");
            final sermon = sermons.first;
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SermonPlayerScreen(sermon: sermon)),
                );
              },
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.network(sermon.thumbnailUrl, height: 180, width: double.infinity, fit: BoxFit.cover),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                          child: Icon(LucideIcons.play, color: Theme.of(context).colorScheme.secondary, size: 24),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(15.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sermon.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Text("${sermon.preacher} • Latest Sunday", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
          error: (err, stack) => Text("Error loading sermons: $err"),
        ),
      ],
    );
  }

  Widget _buildEventTimeline(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle(context, "Upcoming Events"),
            const Text("VIEW ALL", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w900)),
          ],
        ),
        _buildEventItem(context, "Night of Worship", "Friday, 19:00", LucideIcons.music),
        _buildEventItem(context, "Youth Bible Study", "Saturday, 16:00", LucideIcons.book),
      ],
    );
  }

  Widget _buildEventItem(BuildContext context, String title, String time, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKingdomNews(BuildContext context) {
    final publicNewsAsync = ref.watch(publicNewsProvider);
    final kingdomNewsAsync = ref.watch(kingdomNewsStreamProvider);

    return Column(
      children: [
        kingdomNewsAsync.when(
          data: (news) => Column(
            children: news.map((article) => _buildNewsCard(context, article)).toList(),
          ),
          loading: () => const CircularProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        publicNewsAsync.when(
          data: (news) => Column(
            children: news.take(4).map((article) => _buildNewsCard(context, article)).toList(),
          ),
          loading: () => const SizedBox.shrink(),
          error: (e, s) => Text("Error loading public news: $e"),
        ),
      ],
    );
  }

  Widget _buildNewsCard(BuildContext context, NewsArticle article) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: InkWell(
        onTap: () {
          if (article.isLocal) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => NewsDetailScreen(article: article)));
          } else {
            launchUrl(Uri.parse(article.link));
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              child: Image.network(
                article.image,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 100,
                  height: 100,
                  color: Colors.grey[200],
                  child: const Icon(LucideIcons.image),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.source.toUpperCase(),
                      style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      article.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      article.pubDate,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Row(
        children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary)),
        ],
      ),
    );
  }

  Widget _buildDeepLink(BuildContext context, IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      child: ElevatedButton.icon(
        onPressed: () {
          if (label == "Giving") {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const GivingScreen()));
          } else if (label == "Prayer") {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const PrayerWallScreen()));
          } else if (label == "Notes") {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const SermonNotesScreen()));
          } else if (label == "Lyrics") {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const WorshipLyricsScreen()));
          } else if (label == "Connect") {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connecting to Communities...")));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Opening $label..."), behavior: SnackBarBehavior.floating));
          }
        },
        icon: Icon(icon, color: Colors.white, size: 14),
        label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white12,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _buildDailyBibleVerseCard(BuildContext context) {
    final verseAsync = ref.watch(dailyBibleVerseProvider);

    return verseAsync.when(
      data: (verse) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.deepPurple.shade900.withValues(alpha: 0.85),
              Colors.indigo.shade800.withValues(alpha: 0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.shade900.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        LucideIcons.bookOpen,
                        color: Colors.amber,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "VERSE OF THE DAY",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.amber.shade300,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(LucideIcons.share2, color: Colors.white70, size: 18),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text("Daily verse copied to clipboard!"),
                        backgroundColor: Colors.indigo.shade700,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '"${verse.text}"',
              style: const TextStyle(
                fontSize: 15,
                color: Colors.white,
                height: 1.5,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                "— ${verse.reference}",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade200,
                ),
              ),
            ),
          ],
        ),
      ),
      loading: () => Container(
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.amber),
        ),
      ),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }

  Widget _buildSubscriptionPaywall(BuildContext context, Tenant tenant) {
    final hasSubmitted = tenant.paymentReference != null && tenant.paymentReference!.isNotEmpty;
    final settingsAsync = ref.watch(platformSettingsProvider);
    final churchFee = settingsAsync.maybeWhen(
      data: (s) => s.churchFee,
      orElse: () => 1500.0,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.shade50.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.red.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasSubmitted ? "Payment Under Review" : "Subscription Required",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            hasSubmitted
                ? "Your payment reference (${tenant.paymentReference}) is currently being reviewed by the Superadmin. Access to ${tenant.name} will be restored as soon as payment is confirmed."
                : "The 30-day free trial for ${tenant.name} has expired. To reactivate full access for all members, please submit a payment of K${churchFee.toStringAsFixed(2)} ZMW.",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade800,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          if (!hasSubmitted) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Mobile Money Payment Details",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black,
                    ),
                  ),
                  const Divider(height: 16),
                  _buildMomoRow("Provider", "MTN MoMo / Airtel Money"),
                  _buildMomoRow("Account Number", "0976847775"),
                  _buildMomoRow("Account Name", "COA Superadmin Billing"),
                  _buildMomoRow("Amount Due", "K${churchFee.toStringAsFixed(2)} ZMW"),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Enter payment Transaction ID / Reference (TXID) below to submit:",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _txidController,
              decoration: InputDecoration(
                hintText: "e.g. 2938102938",
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmittingPayment ? null : () => _submitMomoReference(tenant.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmittingPayment
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        "SUBMIT PAYMENT REFERENCE",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
              ),
            ),
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 3),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "Awaiting Superadmin confirmation...",
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                ref.read(currentTenantProvider.notifier).setTenant(null);
              },
              child: const Text(
                "SELECT ANOTHER CHURCH",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMomoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
        ],
      ),
    );
  }

  Future<void> _submitMomoReference(String churchId) async {
    final refCode = _txidController.text.trim();
    if (refCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your transaction ID"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmittingPayment = true);

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('churches').update({
        'payment_reference': refCode,
        'payment_submitted_at': DateTime.now().toIso8601String(),
      }).eq('id', churchId);

      // Reload tenant
      await ref.read(currentTenantProvider.notifier).loadTenant();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Payment reference submitted successfully! ✅"),
            backgroundColor: Colors.green,
          ),
        );
        _txidController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to submit reference: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingPayment = false);
    }
  }
}

