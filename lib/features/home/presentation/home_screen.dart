import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:church_on_app/core/widgets/kingdom_logo.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import '../data/live_streaming_service.dart';
import '../data/news_service.dart';
import '../data/sermon_service.dart';
import '../widgets/news_ticker.dart';
import '../widgets/announcement_ticker.dart';
import 'sermon_player_screen.dart';
import 'live_stream_screen.dart';
import 'news_detail_screen.dart';
import 'sermon_library_screen.dart';
import 'event_hub_screen.dart';
import 'universal_search_screen.dart';
import 'package:church_on_app/features/finance/presentation/giving_screen.dart';
import 'package:church_on_app/features/transport/presentation/ride_request_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/marketplace_screen.dart';
import 'package:church_on_app/features/bible/presentation/bible_screen.dart';
import 'package:church_on_app/features/connect/presentation/prayer_wall_screen.dart';
import 'package:church_on_app/features/notebook/presentation/notebook_screen.dart';
import 'branch_locator_screen.dart';
import 'package:church_on_app/features/auth/presentation/select_church_screen.dart';
import 'notifications_screen.dart';
import 'package:church_on_app/features/navigation/presentation/ride_on_scanner_screen.dart';
import 'package:church_on_app/features/modules/logistics/presentation/weather_maps_screen.dart';
import 'package:church_on_app/features/modules/bible_quiz/presentation/bible_quiz_hub_screen.dart';
import 'package:church_on_app/features/modules/navigation/presentation/more_hub_screen.dart';
import 'sermon_notes_screen.dart';
import 'song_lyrics_screen.dart';
import 'package:church_on_app/features/modules/media/presentation/kingdom_radio_screen.dart';
import 'package:church_on_app/features/connect/presentation/create_social_post_screen.dart';
import 'package:church_on_app/features/modules/navigation/presentation/kingdom_life_hub_screen.dart';

import 'package:church_on_app/core/services/notification_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
    final supabase = ref.watch(supabaseServiceProvider);
    final tenant = ref.watch(currentTenantProvider);
    final liveStatus = tenant != null 
        ? ref.watch(liveStatusProvider(tenant.id)).asData?.value 
        : null;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(context, tenant),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AnnouncementTicker(),
                    const SizedBox(height: 20),
                    _buildGreetingHeader(context),
                    const SizedBox(height: 20),
                    if (tenant == null) _buildSmartReminder(context),
                    const SizedBox(height: 20),
                    _buildContextualWidget(context, liveStatus, tenant),
                    const SizedBox(height: 30),
                    _buildQuickActions(context),
                    const SizedBox(height: 30),
                    _buildPromoCarousel(context),
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
                    boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withOpacity(0.3), blurRadius: 8)],
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
              IconButton(
                icon: const Icon(LucideIcons.bell, size: 20),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen())),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
        final name = profile?.name ?? "Believer";
        final coins = profile?.coins ?? 0;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Good Morning,", style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)),
                Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
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
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
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
            onPressed: () {},
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
      height: 200,
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
            colors: [Colors.black.withOpacity(0.8), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.all(25),
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
                      // Maybe show a "Not Live" toast or navigate to schedule
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

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
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
                  if (actions[index]['label'] == "Kingdom Life") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const KingdomLifeHubScreen()));
                  } else if (actions[index]['label'] == "Bible Quiz") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const BibleQuizHubScreen()));
                  } else if (actions[index]['label'] == "Bible") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const BibleScreen())); 
                  } else if (actions[index]['label'] == "Check-in") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const RideOnScannerScreen()));
                  } else if (actions[index]['label'] == "Sermons") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const SermonLibraryScreen()));
                  } else if (actions[index]['label'] == "Events") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const EventHubScreen()));
                  } else if (actions[index]['label'] == "Branches") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const BranchLocatorScreen()));
                  } else if (actions[index]['label'] == "Notebook") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const NotebookScreen()));
                  } else if (actions[index]['label'] == "Radio") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const KingdomRadioScreen()));
                  } else if (actions[index]['label'] == "Kingdom Life") {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const KingdomLifeHubScreen()));
                  }
                },
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 15),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [(actions[index]['color'] as Color).withOpacity(0.8), actions[index]['color'] as Color],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: (actions[index]['color'] as Color).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
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
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
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
                    Colors.black.withOpacity(0.2),
                    Colors.black.withOpacity(0.7),
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
    );
  }

  Widget _buildSparkleGrid(BuildContext context) {
    return MasonryGridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      itemCount: 4,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const MarketplaceScreen()));
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Image.network(
                    "https://images.unsplash.com/photo-1543165796-5426273ea430?w=400&q=60",
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Kingdom Merch", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      Text("Daily Pick", style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
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
            Navigator.push(context, MaterialPageRoute(builder: (context) => const SongLyricsScreen()));
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
}

