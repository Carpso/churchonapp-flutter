import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class DemoChurchScreen extends ConsumerStatefulWidget {
  const DemoChurchScreen({super.key});

  @override
  ConsumerState<DemoChurchScreen> createState() => _DemoChurchScreenState();
}

class _DemoChurchScreenState extends ConsumerState<DemoChurchScreen> {
  bool _isLoading = false;

  Future<void> _startDemo() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final demoEmail = const String.fromEnvironment('DEMO_EMAIL', defaultValue: '');
      final demoPassword = const String.fromEnvironment('DEMO_PASSWORD', defaultValue: '');
      if (demoEmail.isEmpty || demoPassword.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Demo mode not configured. Please sign up.'),
              backgroundColor: Colors.amber,
            ),
          );
        }
        return;
      }
      final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
      final signInRes = await client.auth.signInWithPassword(
        email: demoEmail,
        password: demoPassword,
      );

      if (signInRes.user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Demo unavailable. Please sign up.'),
              backgroundColor: Colors.amber,
            ),
          );
        }
        return;
      }

      final churchesRes =
          await client.from('churches').select().limit(1).maybeSingle();
      if (churchesRes != null) {
        await ref.read(currentTenantProvider.notifier).setTenant(
              Tenant(
                id: churchesRes['id'].toString(),
                name: churchesRes['name']?.toString() ?? 'Demo Church',
                slug: churchesRes['slug']?.toString() ?? 'demo',
                primaryColor: const Color(0xFFFFD700),
                accentColor: const Color(0xFF1A1A1A),
                surfaceColor: scaffoldBg,
                fontFamily: 'Plus Jakarta Sans',
                darkMode: 'light',
              ),
            );
      }

      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Demo login failed: ${e.toString().contains("Invalid login") ? "Please sign up instead" : e}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'DEMO CHURCH',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.church,
                      size: 48,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Life Church',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lusaka, Zambia',
                    style: GoogleFonts.inter(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),
                  _featureItem(LucideIcons.headphones, 'Browse Sermons',
                      'Listen to recorded messages from the sermon library'),
                  const SizedBox(height: 16),
                  _featureItem(LucideIcons.calendarDays, 'Explore Events',
                      'View upcoming church services and conferences'),
                  const SizedBox(height: 16),
                  _featureItem(LucideIcons.shoppingBag, 'Try Marketplace',
                      'Browse digital books and faith-based products'),
                  const SizedBox(height: 16),
                  _featureItem(LucideIcons.wallet, 'Test Giving',
                      'Experience digital tithing and offerings'),
                  const SizedBox(height: 16),
                  _featureItem(LucideIcons.messageCircle, 'Community Feed',
                      'Share testimonies and connect with others'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _startDemo,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Color(0xFFFFD700),
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(LucideIcons.play),
                label: Text(
                  _isLoading ? 'SETTING UP...' : 'TRY DEMO',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No account needed. You\'ll be logged into a sample church '
              'with pre-loaded data to explore all features.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.grey.shade500,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _featureItem(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
