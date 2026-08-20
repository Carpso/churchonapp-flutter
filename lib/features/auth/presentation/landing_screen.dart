import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/expansion_service.dart';
import 'package:church_on_app/core/utils/responsive.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:url_launcher/url_launcher.dart';

class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildStickyNav(context),
            _buildHero(context, ref),
            _buildPartnersSection(context),
            _buildValueProp(context),
            _buildFeatures(context),
            _buildStats(context),
            _buildPricing(context, ref),
            _buildRegistrationBanner(context),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyNav(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.hPadding(context),
        vertical: 25,
      ),
      color: Colors.white,
      child: Responsive.wrap(
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 14,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFDA03),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Image.asset("assets/app_logo.png", errorBuilder: (c, e, s) => const Icon(Icons.church, color: Colors.black)),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "Church On App",
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -1,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                _buildSmallButton("Sign Up", () => context.go('/signup')),
                _buildSmallButton("Member Login", () => context.go('/login')),
                _buildSmallButton("Join Ecosystem", () => context.go('/register-church'), isPrimary: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, WidgetRef ref) {
    final headline = Responsive.displayFont(context, 64, tablet: 48, phone: 34);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: Responsive.isCompact(context) ? 60 : 100,
        bottom: Responsive.isCompact(context) ? 60 : 80,
      ),
      child: Responsive.wrap(
        Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: const Color(0xFFFFCC00).withValues(alpha: 0.3)),
              ),
              child: const Text(
                "✨ CONNECTING CHURCHES THROUGH TECHNOLOGY",
                style: TextStyle(
                  color: Color(0xFFB8860B),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "Connecting Churches\nThrough Technology.",
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: headline,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ),
            const SizedBox(height: 25),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Text(
                    "From Lusaka to Harare, we're uniting churches with a world-class platform for sermons, ride-sharing, digital giving, and deep community engagement.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: Responsive.isCompact(context) ? 17 : 20,
                      color: Colors.black45,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 50),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 20,
              runSpacing: 16,
              children: [
                _buildBigButton(context, "Explore Churches", () => context.go('/select-church')),
                _buildOutlineBigButton(context, "Register Church", () => context.go('/register-church')),
              ],
            ),
            const SizedBox(height: 100),
            _buildPhoneMockup(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneMockup(BuildContext context) {
    const appIcons = <(IconData, String, Color)>[
      (Icons.menu_book, 'Bible', Color(0xFF4CAF50)),
      (Icons.play_circle, 'Sermons', Color(0xFF2196F3)),
      (Icons.wallet, 'Give', Color(0xFFFF9800)),
      (Icons.calendar_today, 'Events', Color(0xFFE91E63)),
      (Icons.store, 'Market', Color(0xFF009688)),
      (Icons.quiz, 'Quiz', Color(0xFF3F51B5)),
      (Icons.directions_car, 'Ride', Color(0xFF673AB7)),
      (Icons.radio, 'Radio', Color(0xFFF44336)),
      (Icons.forum, 'Chat', Color(0xFF00BCD4)),
      (Icons.edit_note, 'Notes', Color(0xFF795548)),
      (Icons.videocam, 'Klips', Color(0xFF9C27B0)),
      (Icons.favorite, 'Prayer', Color(0xFFFF5722)),
    ];
    final phoneWidth = (MediaQuery.of(context).size.width * 0.8).clamp(280.0, 340.0);
    final phoneHeight = phoneWidth * 2.0;
    return Center(
      child: Container(
        width: phoneWidth,
        height: phoneHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(phoneWidth * 0.15),
          border: Border.all(color: Colors.white10, width: 8),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 100, spreadRadius: 10),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(phoneWidth * 0.13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: const Color(0xFF141414),
                child: Column(
                  children: [
                    const SizedBox(height: 34),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        "Church On App",
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.8,
                        ),
                        itemCount: appIcons.length,
                        itemBuilder: (context, i) {
                          return Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3)),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [appIcons[i].$3, appIcons[i].$3.withValues(alpha: 0.7)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(color: appIcons[i].$3.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3)),
                                    ],
                                  ),
                                  child: Icon(appIcons[i].$1, color: Colors.white, size: 22),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  appIcons[i].$2,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Center(
                child: Container(
                  margin: const EdgeInsets.all(18),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFDA03),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: const Color(0xFFFFDA03).withValues(alpha: 0.4), blurRadius: 24)],
                        ),
                        child: Image.asset("assets/app_logo.png", width: 64, height: 64, errorBuilder: (c, e, s) => const Icon(Icons.church, size: 40)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Church On App",
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Connecting Churches Through Technology",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.2, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartnersSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          const Text("JOINING FORCES ACROSS SOUTHERN AFRICA", style: TextStyle(letterSpacing: 3, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black26)),
          const SizedBox(height: 40),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _partnerLogo("ZIMBABWE"),
                _partnerLogo("ZAMBIA"),
                _paymentLogo("assets/logo_airtel.png"),
                _paymentLogo("assets/logo_mtn.png"),
                _paymentLogo("assets/logo_zamtel.png"),
                _partnerLogo("RADIO"),
                _partnerLogo("CARPSO RIDE"),
                _partnerLogo("MOBILE MONEY"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _partnerLogo(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: Colors.black.withValues(alpha: 0.1),
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _paymentLogo(String asset) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Image.asset(asset, height: 40, color: Colors.black.withValues(alpha: 0.1), errorBuilder: (c,e,s) => Container()),
    );
  }

  Widget _buildValueProp(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: Responsive.isCompact(context) ? 60 : 100,
      ),
      color: Colors.white,
      child: Responsive.wrap(
        LayoutBuilder(
          builder: (context, constraints) {
            final avail = constraints.maxWidth;
            final cols = avail >= 960 ? 3 : (avail >= 560 ? 2 : 1);
            final itemWidth = (avail - 32 * (cols - 1)) / cols;
            final itemPadding = Responsive.isCompact(context) ? 28.0 : 40.0;
            return Wrap(
              spacing: 32,
              runSpacing: 32,
              alignment: WrapAlignment.center,
              children: [
                _valueItem(Icons.security, "Security First", "Your congregation's data is protected by enterprise-grade encryption.", itemWidth, itemPadding),
                _valueItem(Icons.flash_on, "Real-time Sync", "Instant updates for sermons, events, and community chats.", itemWidth, itemPadding),
                _valueItem(Icons.public, "Borderless", "Connect with members whether they are in the pews or abroad.", itemWidth, itemPadding),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _valueItem(IconData icon, String title, String desc, double width, double padding) {
    return Container(
      width: width,
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          Icon(icon, size: 48, color: const Color(0xFFFFCC00)),
          const SizedBox(height: 25),
          Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 15),
          Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black45, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildFeatures(BuildContext context) {
    final titleSize = Responsive.displayFont(context, 48, tablet: 40, phone: 30);
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: Responsive.isCompact(context) ? 70 : 120,
        horizontal: Responsive.hPadding(context),
      ),
      child: Responsive.wrap(
        Column(
          children: [
            Text("CHURCH OPERATING SYSTEM", style: TextStyle(letterSpacing: 2, color: const Color(0xFF7A5C00), fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 20),
            Text("Uniting the Faithful.", style: GoogleFonts.plusJakartaSans(fontSize: titleSize, fontWeight: FontWeight.w900)),
            const SizedBox(height: 15),
            Text("Everything your church needs—in one digital ecosystem.", style: TextStyle(fontSize: Responsive.isCompact(context) ? 15 : 18, color: Colors.black45, height: 1.5)),
            const SizedBox(height: 80),
            LayoutBuilder(
              builder: (context, constraints) {
                final avail = constraints.maxWidth;
                final cols = avail >= 1100 ? 3 : (avail >= 660 ? 2 : 1);
                final cardWidth = (avail - 30 * (cols - 1)) / cols;
                return Wrap(
                  spacing: 30,
                  runSpacing: 30,
                  alignment: WrapAlignment.center,
                  children: [
                    _featureCard(context, Icons.menu_book, "Holy Bible", "Read, study, and memorize Scripture with multiple translations and audio.", cardWidth),
                    _featureCard(context, Icons.play_circle, "Sermons & Media", "Live streaming, recorded sermons, and worship lyrics in one place.", cardWidth),
                    _featureCard(context, Icons.wallet, "Digital Giving", "Tithes, offerings, and fundraising via MTN, Airtel, and Zamtel mobile money.", cardWidth),
                    _featureCard(context, Icons.calendar_today, "Events & Calendars", "Never miss a conference or fellowship again—with ticketing and check-in.", cardWidth),
                    _featureCard(context, Icons.store, "Marketplace", "Buy and sell within your church community—books, crafts, and more.", cardWidth),
                    _featureCard(context, Icons.quiz, "Bible Quiz", "Compete in Scripture knowledge challenges with your church and beyond.", cardWidth),
                    _featureCard(context, Icons.directions_car, "Ride Sharing", "Carpso Ride—safe, affordable church commutes, deliveries, and SOS.", cardWidth),
                    _featureCard(context, Icons.radio, "Kingdom Radio", "Broadcasting the Word 24/7 with worship music across the continent.", cardWidth),
                    _featureCard(context, Icons.forum, "Community", "Prayer wall, chat, Klips, testimonies, and pastor-led small groups.", cardWidth),
                    _featureCard(context, Icons.edit_note, "Notebook", "Sermon notes, personal journaling, and AI-powered study tools.", cardWidth),
                    _featureCard(context, Icons.dashboard, "Church Micro-sites", "Every branch gets its own digital home with website builder.", cardWidth),
                    _featureCard(context, Icons.volunteer_activism, "Charity & Missions", "Organize giving and track impact for those who need it most.", cardWidth),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureCard(BuildContext context, IconData icon, String title, String desc, double width) {
    return Container(
      width: width,
      padding: EdgeInsets.all(Responsive.isCompact(context) ? 26 : 40),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF9E3), Color(0xFFFFF0C2)],
        ),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: const Color(0xFFFFDA03).withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: const Color(0xFFFFDA03).withValues(alpha: 0.15), blurRadius: 40, offset: const Offset(0, 20)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, color: const Color(0xFFFFB800), size: 32),
          ),
          const SizedBox(height: 30),
          Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 24, color: const Color(0xFF1A1A1A))),
          const SizedBox(height: 15),
          Text(desc, style: const TextStyle(color: Color(0xFF5A5240), fontSize: 16, height: 1.6)),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context) {
    final dense = Responsive.isCompact(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: dense ? 60 : 100),
      child: Responsive.wrap(
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          runSpacing: 24,
          children: [
            _statItem("500+", "Churches Onboarded", dense),
            _statItem("1M+", "Members Connected", dense),
            _statItem("100%", "Service Uptime", dense),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String val, String label, bool dense) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: dense ? 16 : 60),
      child: Column(
        children: [
          Text(val, style: GoogleFonts.plusJakartaSans(fontSize: dense ? 34 : 48, fontWeight: FontWeight.w900, color: const Color(0xFFFFDA03))),
          Text(label, style: const TextStyle(color: Colors.black26, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildPricing(BuildContext context, WidgetRef ref) {
    final titleSize = Responsive.displayFont(context, 48, tablet: 40, phone: 30);
    // Live plan pricing from platform_settings (synced with the admin
    // Subscription Pricing editor) so the landing page never shows stale
    // hardcoded amounts.
    final cfg = ref.watch(remoteConfigProvider).value;
    final onboardingFee = cfg?.getDouble('onboarding_fee', 500) ?? 500;
    final goldMonthly = cfg?.getDouble('gold_monthly_fee', 100) ?? 100;
    final platinumMonthly = cfg?.getDouble('platinum_monthly_fee', 500) ?? 500;
    final goldText = 'K${goldMonthly.toStringAsFixed(0)}/mo';
    final platinumText = 'K${platinumMonthly.toStringAsFixed(0)}/mo';
    final onboardingText = 'K${onboardingFee.toStringAsFixed(0)}';
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: Responsive.isCompact(context) ? 70 : 120,
        horizontal: Responsive.hPadding(context),
      ),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Responsive.wrap(
        Column(
          children: [
            Text("CHURCH PROMO 🚀", style: TextStyle(letterSpacing: 2, color: const Color(0xFF7A5C00), fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 20),
            Text("Invest in Your Digital Future.", style: GoogleFonts.plusJakartaSans(fontSize: titleSize, fontWeight: FontWeight.w900)),
            const SizedBox(height: 80),
            LayoutBuilder(
              builder: (context, constraints) {
                final avail = constraints.maxWidth;
                final cols = avail >= 1000 ? 4 : (avail >= 640 ? 2 : 1);
                final cardWidth = (avail - 30 * (cols - 1)) / cols;
                return Wrap(
                  spacing: 30,
                  runSpacing: 30,
                  alignment: WrapAlignment.center,
                  children: [
                    _pricingCard(
                      "Churches", goldText, "Free setup",
                      ["Free Silver plan forever", "Gold $goldText • Platinum $platinumText", "One-time $onboardingText onboarding fee", "Digital Tithes & Offerings"],
                      isFeatured: true,
                      onTap: () => context.go('/register-church'),
                      width: cardWidth,
                    ),
                    _pricingCard(
                      "Bookshops", "K0", "onboarding",
                      ["Digital Storefront", "Inventory Management", "Secure Payments", "10% Commission"],
                      onTap: () => context.go('/signup'),
                      width: cardWidth,
                    ),
                    _pricingCard(
                      "Vendors", "K0", "onboarding",
                      ["Sell Goods & Services", "Integrated Delivery", "Instant Payouts", "10% Commission"],
                      onTap: () => context.go('/signup'),
                      width: cardWidth,
                    ),
                    _pricingCard(
                      "Drivers", "K0", "onboarding",
                      ["Flexible Hours", "In-App Navigation", "Instant Payouts", "10% Commission"],
                      onTap: () => context.go('/signup'),
                      width: cardWidth,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _pricingCard(String title, String price, String period, List<String> features, {bool isFeatured = false, VoidCallback? onTap, double? width}) {
    return Container(
      width: width ?? 280,
      padding: const EdgeInsets.all(35),
      decoration: BoxDecoration(
        color: isFeatured ? Colors.black : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 30, offset: const Offset(0, 15)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isFeatured ? Colors.white : Colors.black)),
          const SizedBox(height: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(price, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 32, height: 1.1, color: isFeatured ? const Color(0xFFFFDA03) : Colors.black)),
              const SizedBox(height: 4),
              Text(period, style: TextStyle(fontSize: 13, color: isFeatured ? Colors.white70 : Colors.black45, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 30),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: isFeatured ? const Color(0xFFFFDA03) : Colors.green),
                const SizedBox(width: 10),
                Expanded(child: Text(f, style: TextStyle(fontSize: 13, color: isFeatured ? Colors.white70 : Colors.black87))),
              ],
            ),
          )),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: isFeatured ? const Color(0xFFFFDA03) : Colors.black,
                foregroundColor: isFeatured ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("Get Started", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationBanner(BuildContext context) {
    final dense = Responsive.isCompact(context);
    return Responsive.wrap(
      Container(
        margin: EdgeInsets.symmetric(vertical: dense ? 16 : 60),
        padding: EdgeInsets.all(dense ? 28 : 80),
        decoration: BoxDecoration(
          color: const Color(0xFFFFCC00),
          borderRadius: BorderRadius.circular(dense ? 28 : 50),
        ),
        child: Column(
          children: [
            Text(
              "Ready to digitalize your ministry?",
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: dense ? 24 : 36, fontWeight: FontWeight.w900, color: Colors.black),
            ),
            const SizedBox(height: 20),
            const Text("Join the fastest growing ecosystem today.", style: TextStyle(fontSize: 18, color: Colors.black54)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => context.go('/register-church'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: dense ? 26 : 50, vertical: dense ? 18 : 25),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                "REGISTER YOUR CHURCH NOW",
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 100,
        bottom: 40,
        left: Responsive.hPadding(context),
        right: Responsive.hPadding(context),
      ),
      color: const Color(0xFF1A1A1A),
      child: Responsive.wrap(
        Column(
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.start,
              runSpacing: 40,
              spacing: 60,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset("assets/app_logo.png", height: 30, errorBuilder: (c,e,s) => const Icon(Icons.church, color: Colors.white)),
                        const SizedBox(width: 10),
                        Text("Church On App", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text("Connecting Churches Through Technology.", style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                    const SizedBox(height: 25),
                    _footerContact(Icons.phone, "+260 968 551 110"),
                    _footerContact(Icons.mail, "hello@churchonapp.com"),
                  ],
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.start,
                  runSpacing: 40,
                  spacing: 60,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _footerHeading("Features"),
                        _footerLink("Sermons & Teachings", onTap: () => context.push('/sermons')),
                        _footerLink("Events & Calendars", onTap: () => context.push('/events')),
                        _footerLink("Klips", onTap: () => context.push('/kingdom-klips')),
                        _footerLink("Bible Quiz", onTap: () => context.push('/quiz')),
                        _footerLink("Carpso Ride", onTap: () => context.push('/ride')),
                        _footerLink("Jobs Portal", onTap: () => context.push('/jobs')),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _footerHeading("Resources"),
                        _footerLink("Privacy Policy", onTap: () => context.push('/privacy')),
                        _footerLink("Terms of Service", onTap: () => context.push('/terms')),
                        _footerLink("About Us", onTap: () => context.push('/about')),
                        _footerLink("Support", onTap: () => context.push('/support')),
                        _footerLink("Contact Us", onTap: () async {
                          final url = Uri.parse("mailto:hello@churchonapp.com");
                          if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.inAppWebView);
                        }),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 40),
            Center(
              child: TextButton.icon(
                onPressed: () => _showExpansionDialog(context),
                icon: const Icon(Icons.add_location_alt, color: Colors.amber),
                label: const Text("Tell us which church to add next", style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 40),
            const Divider(color: Colors.white12),
            const SizedBox(height: 20),
            Text("© 2026 Church On App Global. Powered by Carpso Solutions.", style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _footerContact(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Icon(icon, color: Colors.white24, size: 20),
          const SizedBox(width: 15),
          Text(text, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _footerHeading(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Text(text, style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    );
  }

  Widget _footerLink(String text, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 13)),
      ),
    );
  }

  Widget _buildSmallButton(String text, VoidCallback onTap, {bool isPrimary = false}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? const Color(0xFFFFDA03) : Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildBigButton(BuildContext context, String text, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildOutlineBigButton(BuildContext context, String text, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        side: const BorderSide(color: Colors.black, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  void _showExpansionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final churchCtrl = TextEditingController();
          final locCtrl = TextEditingController();
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            title: const Text("Join the Expansion", style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Don't see your church? Let us know and we'll prioritize bringing them online!"),
                const SizedBox(height: 20),
                TextField(
                  controller: churchCtrl,
                  decoration: InputDecoration(
                    labelText: "Church Name",
                    prefixIcon: const Icon(Icons.church),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: locCtrl,
                  decoration: InputDecoration(
                    labelText: "Location (City/Country)",
                    prefixIcon: const Icon(Icons.map),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Later")),
              ElevatedButton(
                onPressed: () async {
                  if (churchCtrl.text.isNotEmpty) {
                    await ref.read(expansionServiceProvider).trackChurchInterest(
                      churchName: churchCtrl.text,
                      location: locCtrl.text,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Thanks! We've logged your interest.")),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("Notify Me"),
              ),
            ],
          );
        },
      ),
    );
  }
}
