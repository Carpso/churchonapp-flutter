import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class SystemDocsScreen extends ConsumerWidget {
  const SystemDocsScreen({super.key});

  static const _sections = [
    _DocSection(
      title: 'Getting Started Guide',
      icon: LucideIcons.rocket,
      content: [
        'Welcome to Church On App — your all-in-one church management and community platform.',
        '',
        '\u2022  Create an account using email or Google sign-in.',
        '\u2022  Select or create your church branch (tenant).',
        '\u2022  Customize your profile with name, avatar, and contact info.',
        '\u2022  Explore the Home dashboard with your daily sermon, events, and quick actions.',
        '\u2022  Access the Sermon Library to listen to recorded messages.',
        '\u2022  Use the Connect tab to share testimonies and engage with the community.',
        '\u2022  Visit the Marketplace to purchase books and digital content.',
        '\u2022  Enable Driver/Vendor mode in Profile to offer logistics services.',
      ],
    ),
    _DocSection(
      title: 'Admin Manual',
      icon: LucideIcons.shield,
      content: [
        'The Admin Console provides comprehensive church management tools.',
        '',
        '\u2022  Member Management: View, verify, and manage all registered members.',
        '\u2022  Baptism Registry: Record and certify baptism events with certificates.',
        '\u2022  Ministry Management: Create and oversee ministry groups and leaders.',
        '\u2022  Event Scheduling: Plan services, conferences, and church-wide events.',
        '\u2022  Financial Dashboard: Track tithes, offerings, and platform revenue.',
        '\u2022  Media Upload: Publish sermons, videos, and Kingdom Klips.',
        '\u2022  Global Broadcast: Send push notifications and church alerts.',
        '\u2022  Report Creator: Generate custom statistical reports.',
        '\u2022  Role Management: Assign and approve custom user roles.',
        '\u2022  Payout Settlement: Approve Mobile Money worker payouts.',
      ],
    ),
    _DocSection(
      title: 'API Reference',
      icon: LucideIcons.code,
      content: [
        'Church On App exposes RESTful and real-time APIs via Supabase.',
        '',
        '\u2022  Authentication: /auth/v1/* \u2014 sign-up, sign-in, magic link, OAuth.',
        '\u2022  Database: /rest/v1/* \u2014 full CRUD on profiles, churches, transactions.',
        '\u2022  Realtime: /realtime/v1/* \u2014 WebSocket subscriptions for live feeds.',
        '\u2022  Storage: /storage/v1/* \u2014 upload and serve media files via R2/S3.',
        '\u2022  Edge Functions: /functions/v1/* \u2014 serverless backend logic.',
        '\u2022  Row-Level Security (RLS) policies protect all tenant-scoped data.',
        '\u2022  All requests require a valid JWT from Supabase Auth.',
        '\u2022  Rate limits apply: 30 req/s per IP on REST, 10 req/s on Functions.',
      ],
    ),
    _DocSection(
      title: 'Deployment Guide',
      icon: LucideIcons.server,
      content: [
        'Deploying Church On App for production use.',
        '',
        '\u2022  Flutter Web: Run `flutter build web` and deploy to Cloudflare Pages.',
        '\u2022  Mobile (Android): Build APK/AAB with `flutter build apk \u2014release`.',
        '\u2022  Mobile (iOS): Open `ios/Runner.xcworkspace` in Xcode and archive.',
        '\u2022  Supabase: Run all migrations from `supabase/migrations/` folder.',
        '\u2022  Environment: Copy `.env.example` to `.env`, fill in Supabase keys.',
        '\u2022  Edge Functions: Deploy with `supabase functions deploy`.',
        '\u2022  Storage: Configure R2 bucket with public access for media assets.',
        '\u2022  Monitoring: Use Supabase Logs and Grafana for observability.',
        '\u2022  Backups: Enable daily database backups in Supabase dashboard.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null || !profile.isAdminOrHigher) {
          return Scaffold(
            backgroundColor: const Color(0xFFFFFAEB),
            appBar: AppBar(
              title: const Text('System Documentation'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.black87,
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.lock, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'Admin access required',
                    style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }
        return _DocListScreen();
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFFFFFAEB),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: const Color(0xFFFFFAEB),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _DocListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: Text(
          'SYSTEM DOCUMENTATION',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 2,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        itemCount: SystemDocsScreen._sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final section = SystemDocsScreen._sections[index];
          return _DocCard(section: section);
        },
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final _DocSection section;
  const _DocCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _DocDetailScreen(section: section),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFAEB),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(section.icon, color: Colors.black87, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${section.content.length} topics',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

class _DocDetailScreen extends StatelessWidget {
  final _DocSection section;
  const _DocDetailScreen({required this.section});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: Text(
          section.title.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: 1.5,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: section.content.map((line) {
                  if (line.isEmpty) return const SizedBox(height: 8);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      line,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.6,
                        color: line.startsWith('\u2022')
                            ? Colors.black87
                            : Colors.grey.shade700,
                        fontWeight: line.startsWith('\u2022')
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocSection {
  final String title;
  final IconData icon;
  final List<String> content;

  const _DocSection({
    required this.title,
    required this.icon,
    required this.content,
  });
}
