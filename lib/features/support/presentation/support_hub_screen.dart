import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

// Feature screens for direct navigation from How-To guides
import '../../finance/presentation/giving_screen.dart';
import '../../finance/presentation/coa_missions_donate_screen.dart';
import '../../finance/presentation/buy_coins_screen.dart';
import '../../finance/presentation/partner_redemption_screen.dart';
import '../../modules/bible_quiz/presentation/bible_quiz_hub_screen.dart';
import '../../connect/presentation/prayer_wall_screen.dart';
import '../../profile/presentation/kyc_verification_screen.dart';

class SupportHubScreen extends ConsumerStatefulWidget {
  const SupportHubScreen({super.key});

  @override
  ConsumerState<SupportHubScreen> createState() => _SupportHubScreenState();
}

class _SupportHubScreenState extends ConsumerState<SupportHubScreen> {
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;
  
  // Custom interactive guides states
  int _selectedTab = 0; // 0 = How-To Guides, 1 = Submit Ticket
  String _selectedCategory = 'Wallet'; // Categories: Wallet, Word, Community, Logistics, Command

  Future<void> _submitTicket() async {
    if (_subjectController.text.isEmpty || _descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields"), backgroundColor: Colors.amber),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client.from('tickets').insert({
        'user_id': user.id,
        'subject': _subjectController.text,
        'description': _descriptionController.text,
        'status': 'open',
        'priority': 'medium',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ticket submitted successfully! Our team will review it."), backgroundColor: Colors.green),
        );
        _subjectController.clear();
        _descriptionController.clear();
        setState(() {
          _selectedTab = 0; // Redirect back to guides or list
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error submitting ticket: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // Warm premium background
      appBar: AppBar(
        title: Text(
          "SUPPORT & GUIDES",
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Custom Sliding Tab Bar
            _CustomSlidingTabBar(
              selectedIndex: _selectedTab,
              onTabSelected: (index) {
                setState(() {
                  _selectedTab = index;
                });
              },
            ),
            const SizedBox(height: 30),

            // Display content based on active tab
            _selectedTab == 0 ? _buildGuidesTab(theme) : _buildTicketsTab(theme),
          ],
        ),
      ),
    );
  }

  // MARK: - Guides Tab
  Widget _buildGuidesTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Interactive Guides",
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Learn how to navigate tithing, quiz arenas, live audio feeds, and transport modules step-by-step.",
          style: GoogleFonts.inter(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 25),

        // Horizontal Category Selector Chips
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _buildCategoryChip("Wallet", LucideIcons.wallet),
              _buildCategoryChip("Word & Radio", LucideIcons.headphones),
              _buildCategoryChip("Community", LucideIcons.users),
              _buildCategoryChip("Logistics", LucideIcons.car),
              _buildCategoryChip("Ministry", LucideIcons.crown),
            ],
          ),
        ),
        const SizedBox(height: 25),

        // Guides list filtered by selected category
        ..._getFilteredGuides(),
      ],
    );
  }

  Widget _buildCategoryChip(String categoryName, IconData icon) {
    final theme = Theme.of(context);
    final isSelected = _selectedCategory == categoryName;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = categoryName;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.onSurface : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.05),
            width: 1.5,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? theme.primaryColor : theme.colorScheme.onSurface.withValues(alpha: 0.54),
            ),
            const SizedBox(width: 8),
            Text(
              categoryName,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isSelected ? theme.colorScheme.surface : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _getFilteredGuides() {
    switch (_selectedCategory) {
      case 'Wallet':
        return [
          _GuideExpansionTile(
            icon: LucideIcons.coins,
            title: "Daily Church Coins (CC)",
            description: "Claim your daily rewards to spend on ads, books, and partner offers.",
            steps: const [
              "Navigate to your Profile Tab by clicking the user avatar on the bottom-right.",
              "Locate the Wallet section at the top of the screen.",
              "Click the COLLECT button to claim your daily CC reward instantly.",
              "Daily claims accumulate. Make sure to log in every day to keep your streak!"
            ],
            actionLabel: "Open Profile",
            onActionPressed: () => context.push('/profile'),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.shoppingCart,
            title: "Buy Church Coins",
            description: "Purchase coins with Mobile Money or Card to unlock premium features.",
            steps: const [
              "Go to Profile > Wallet and tap BUY CC.",
              "Choose a coin package (100 CC = K10 up to 2500 CC = K150).",
              "Select your payment method: MTN MoMo, Airtel Money, or Card.",
              "Complete the payment via the secure Lipila gateway.",
              "Coins are credited instantly to your balance."
            ],
            actionLabel: "Buy Coins",
            onActionPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyCoinsScreen())),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.badgePercent,
            title: "Redeem Coins at Partners",
            description: "Spend your Church Coins at bookshops, coffee shops, and partner businesses.",
            steps: const [
              "Go to Profile > Wallet and tap REDEEM.",
              "Browse available offers from partner bookshops, coffee shops, and more.",
              "Tap REDEEM on an offer you can afford (check your CC balance).",
              "Confirm the redemption — you'll get a confirmation code.",
              "Present the code at the partner location to collect your item."
            ],
            actionLabel: "Browse Partners",
            onActionPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartnerRedemptionScreen())),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.send,
            title: "Tithing & Digital Giving",
            description: "Contribute to local branches and ministries safely via mobile money.",
            steps: const [
              "On your Home Dashboard or Profile wallet, tap the GIVE button.",
              "Specify the collection type (Tithe, Offering, Mission, Building Fund).",
              "Enter the amount and confirm the MoMo transaction fee.",
              "Select Mobile Money as your payment method.",
              "Input your payment phone number and complete the secure transaction prompt."
            ],
            actionLabel: "Give Now",
            onActionPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GivingScreen())),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.shieldCheck,
            title: "Membership KYC Verification",
            description: "Validate your account identity to securely use high-limit features.",
            steps: const [
              "Go to the Profile Tab and click KYC Verification under Account & Trust.",
              "Type in your official name, date of birth, and identity number (NRC/Passport).",
              "Upload a clear photo of your ID document and a verification selfie.",
              "Submit details. Our team will review and verify your identity within 24 hours."
            ],
            actionLabel: "Verify Identity",
            onActionPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KycVerificationScreen())),
          ),
        ];
      case 'Word & Radio':
        return [
          _GuideExpansionTile(
            icon: LucideIcons.tv,
            title: "Live Stream Experience",
            description: "Tune in live during Sunday service and sabaths.",
            steps: const [
              "Open the Home Tab and look at the Sunday Experience banner.",
              "If the service is active, a red LIVE indicator will display. Tap JOIN LIVE.",
              "Inside the player screen, tap Notes at the bottom to open a dedicated scratchpad.",
              "Tap Lyrics next to it to display the current hymn or lyrics to sing along."
            ],
            actionLabel: "Go Home Dashboard",
            onActionPressed: () => context.go('/'),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.folderHeart,
            title: "Sermon Vault & Podcasts",
            description: "Filter and stream recorded sermons offline.",
            steps: const [
              "Tap the Headphones icon on the bottom navigation bar.",
              "Use categories (Miracles, Bible, Faith) or the search bar at the top to filter.",
              "Tap any sermon card to initiate the media player.",
              "You can minimize the player to let sermon audio play in the background."
            ],
            actionLabel: "Browse Sermons",
            onActionPressed: () => context.push('/sermons'),
          ),
        ];
      case 'Community':
        return [
          _GuideExpansionTile(
            icon: LucideIcons.pencil,
            title: "Sharing Testimonies on Feed",
            description: "Publish your testimonies and encourage the church community.",
            steps: const [
              "Go to the Connect Tab on the bottom navigation bar.",
              "Click the red '+' floating button in the bottom right corner.",
              "Write your text, attach premium images if desired, and click PUBLISH.",
              "The post will immediately appear on the live community feed for discussion."
            ],
            actionLabel: "Open Connect Feed",
            onActionPressed: () => context.push('/connect'),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.flame,
            title: "Prayer Wall Requests",
            description: "Request group prayers or stand in intercession for others.",
            steps: const [
              "Open the Profile Tab, select Digital Assets, and click Prayer Wall.",
              "Click the Add Prayer button at the top of the wall.",
              "Draft your prayer request details (you can choose to post anonymously).",
              "Submit. Members can see your request and tap the Flame Icon to register intercessions."
            ],
            actionLabel: "Open Prayer Wall",
            onActionPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrayerWallScreen())),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.helpCircle,
            title: "Bible Quiz Arena",
            description: "Challenge your scriptural knowledge and climb the ranks.",
            steps: const [
              "Go to your Home Tab, select Quick Actions, and tap Bible Quiz.",
              "Unlock a quiz card by paying the requested amount of Church Coins.",
              "Tap Start to answer 10 questions before the timers run out.",
              "Check the Leaderboards to see weekly prize standings for the top scorers!"
            ],
            actionLabel: "Enter Quiz Arena",
            onActionPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BibleQuizHubScreen())),
          ),
        ];
      case 'Logistics':
        return [
          _GuideExpansionTile(
            icon: LucideIcons.mapPin,
            title: "Booking a Carpso Ride",
            description: "Request logistics or transport to weekly church services.",
            steps: const [
              "Click the floating Car Icon in the center of your bottom navigation bar.",
              "Enter your location details and pin your pick-up spot on the interactive map.",
              "Tap Book Ride. The app matches you with an active, on-duty church driver.",
              "Keep the screen active to trace your driver's real-time ETA on the map."
            ],
            actionLabel: "Book Transport",
            onActionPressed: () => context.push('/ride'),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.zap,
            title: "Driver / Vendor Duty Mode",
            description: "Log in as an active logistics driver or church marketplace seller.",
            steps: const [
              "Verify that you are registered as a driver or vendor in the system.",
              "Navigate to your Profile screen.",
              "In the top-right of your Wallet, toggle your switch status from OFF DUTY to ON DUTY.",
              "Click COMMAND inside the card to manage incoming ride requests or active orders."
            ],
            actionLabel: "Go to Profile",
            onActionPressed: () => context.push('/profile'),
          ),
        ];
      case 'Ministry':
        return [
          _GuideExpansionTile(
            icon: LucideIcons.scroll,
            title: "Pastor Branch Reports",
            description: "Log weekly metrics, attendance, and branch statistics for the COA Team.",
            steps: const [
              "Authorized Pastors should head to their Profile Tab.",
              "Select Submit Report to COA Team inside the Ministry & Command section.",
              "Enter attendance counts, local offerings, branch growth charts, and testimonies.",
              "Confirm and click Submit to securely index the report in the diocesan vault."
            ],
            actionLabel: "Go to Profile",
            onActionPressed: () => context.push('/profile'),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.bookOpen,
            title: "Branch Financial Ledgers",
            description: "For church treasurers to review cashflows and publish statements.",
            steps: const [
              "Authorized Ledger Managers can navigate to Profile > Financial Ledger.",
              "Review automated transaction flowcharts containing tithing, collections, and payouts.",
              "Filter records by date or transaction type.",
              "Tap Export Report to download an official PDF statement for parish boards."
            ],
            actionLabel: "Go to Profile",
            onActionPressed: () => context.push('/profile'),
          ),
          _GuideExpansionTile(
            icon: LucideIcons.heart,
            title: "COA Missions Donate",
            description: "Support the Church On App missions — development, outreach, and expansion.",
            steps: const [
              "Navigate to your Profile Tab and tap COA Missions Donate.",
              "Choose a purpose: In-House Missions, App Development, Community Outreach, or General Support.",
              "Enter your donation amount or select a quick-amount button.",
              "Confirm payment via mobile money. Your donation supports the global COA mission."
            ],
            actionLabel: "Donate Now",
            onActionPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoaMissionsDonateScreen())),
          ),
        ];
      default:
        return [];
    }
  }

  // MARK: - Submit Ticket Tab
  Widget _buildTicketsTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "How can we help you?",
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Submit a technical ticket. Our administrative and IT teams review inquiries within 24 hours.",
          style: GoogleFonts.inter(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 30),
        
        _buildTextField(theme, "Subject", _subjectController, "e.g. Daily coins reward not accumulating"),
        const SizedBox(height: 20),
        _buildTextField(theme, "Description", _descriptionController, "Please describe the problem in detail...", maxLines: 5),
        const SizedBox(height: 30),
        
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitTicket,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.onSurface,
            foregroundColor: theme.colorScheme.surface,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: _isSubmitting 
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: theme.primaryColor, strokeWidth: 2),
              )
            : Text(
                "SUBMIT SUPPORT TICKET", 
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13),
              ),
        ),
        
        const SizedBox(height: 40),
        Text(
          "YOUR PREVIOUS TICKETS", 
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), letterSpacing: 2),
        ),
        const SizedBox(height: 15),
        _buildTicketsList(theme),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildTextField(ThemeData theme, String label, TextEditingController controller, String hint, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label, 
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.inter(fontSize: 14, color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 13),
            filled: true,
            fillColor: theme.colorScheme.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.05), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: theme.primaryColor, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildTicketsList(ThemeData theme) {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return Container(
        padding: const EdgeInsets.all(30),
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.userCheck, color: theme.colorScheme.onSurface.withValues(alpha: 0.3), size: 40),
            const SizedBox(height: 10),
            Text(
              "Please log in to see tickets.", 
              style: GoogleFonts.inter(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: client.from('tickets').stream(primaryKey: ['id']).eq('user_id', user.id).order('created_at'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: theme.primaryColor));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(30),
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                Icon(LucideIcons.ticket, color: theme.colorScheme.onSurface.withValues(alpha: 0.3), size: 36),
                const SizedBox(height: 10),
                Text(
                  "No active support tickets found", 
                  style: GoogleFonts.inter(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 13),
                ),
              ],
            ),
          );
        }

        final tickets = snapshot.data!;
        return Column(
          children: tickets.map((t) => _buildTicketItem(theme, t)).toList(),
        );
      },
    );
  }

  Widget _buildTicketItem(ThemeData theme, Map<String, dynamic> ticket) {
    final status = ticket['status'] ?? 'open';
    final color = StatusColor.fromString(context, status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(LucideIcons.info, color: color, size: 18),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket['subject'] ?? 'No Subject', 
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 3),
                Text(
                  status.toUpperCase(), 
                  style: GoogleFonts.plusJakartaSans(color: color, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, color: theme.colorScheme.onSurface.withValues(alpha: 0.2), size: 14),
        ],
      ),
    );
  }
}

// MARK: - Sliding Tab Bar Widget
class _CustomSlidingTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const _CustomSlidingTabBar({
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                left: selectedIndex == 0 ? 0 : tabWidth,
                right: selectedIndex == 0 ? tabWidth : 0,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.primaryColor, // Gold highlight
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onTabSelected(0),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Text(
                          "HOW-TO GUIDES",
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            color: selectedIndex == 0 ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onTabSelected(1),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Text(
                          "SUBMIT TICKET",
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            color: selectedIndex == 1 ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// MARK: - Guide Expansion Tile Widget
class _GuideExpansionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<String> steps;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  const _GuideExpansionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.steps,
    this.actionLabel,
    this.onActionPressed,
  });

  @override
  State<_GuideExpansionTile> createState() => _GuideExpansionTileState();
}

class _GuideExpansionTileState extends State<_GuideExpansionTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isExpanded ? theme.primaryColor.withValues(alpha: 0.5) : theme.colorScheme.onSurface.withValues(alpha: 0.05),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          onExpansionChanged: (expanded) {
            setState(() {
              _isExpanded = expanded;
            });
          },
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isExpanded ? theme.primaryColor.withValues(alpha: 0.1) : theme.scaffoldBackgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, color: _isExpanded ? theme.primaryColor : theme.colorScheme.onSurface, size: 20),
          ),
          title: Text(
            widget.title,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: !_isExpanded
              ? Text(
                  widget.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                )
              : null,
          trailing: Icon(
            _isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            color: _isExpanded ? theme.primaryColor : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            size: 16,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 15),
                  Text(
                    widget.description,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 15),
                  ...widget.steps.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final step = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: theme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "${idx + 1}",
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              step,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (widget.actionLabel != null && widget.onActionPressed != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: widget.onActionPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.onSurface,
                          foregroundColor: theme.colorScheme.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          widget.actionLabel!.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
