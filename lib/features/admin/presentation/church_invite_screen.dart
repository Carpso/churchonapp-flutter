import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/widgets/qr_code_with_logo.dart';

/// Smart church invitation screen for pastors/tenant leaders.
///
/// Provides 6 ways to invite members:
/// 1. Deep Link — https://churchonapp.com/join?code={code}
/// 2. QR Code — Scannable from another phone's camera
/// 3. WhatsApp — Pre-filled message with deep link
/// 4. SMS — Pre-filled text message with deep link
/// 5. Native Share — System share sheet (any app)
/// 6. Copy Code — For manual entry in the app
class ChurchInviteScreen extends ConsumerStatefulWidget {
  const ChurchInviteScreen({super.key});

  @override
  ConsumerState<ChurchInviteScreen> createState() => _ChurchInviteScreenState();
}

class _ChurchInviteScreenState extends ConsumerState<ChurchInviteScreen> {
  String? _inviteCode;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchInviteCode();
  }

  Future<void> _fetchInviteCode() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final church = await Supabase.instance.client
          .from('churches')
          .select('country')
          .eq('tenant_id', tenant.id)
          .maybeSingle();
      final country = church?['country']?.toString() ?? 'ZM';

      final userId = ref.read(profileProvider).value?.id ?? '';
      final result = await Supabase.instance.client
          .from('generated_codes')
          .select('code_value')
          .eq('code_type', 'tenant')
          .eq('country_iso', country)
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      setState(() {
        _inviteCode = result?['code_value'] as String?;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching invite code: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);

    if (tenant == null || _loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_inviteCode == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text("Invite Members")),
        body: const Center(child: Text("No invite code found. Please re-register your church.")),
      );
    }

    final churchName = tenant.name;
    final inviteCode = _inviteCode!;
    final deepLink = "https://churchonapp.com/join?code=$inviteCode";

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Invite Members"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(LucideIcons.userPlus, size: 56, color: Colors.amber),
            const SizedBox(height: 16),
            Text(
              "Invite to $churchName",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Share this invite with your members. They can join by tapping the link, scanning the QR code, or entering the code manually.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 32),

            // ─── 1. Deep Link Card ──────────────────────────────
            _InviteCard(
              icon: LucideIcons.link,
              title: "Invite Link",
              subtitle: "Tap to open in the app",
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            deepLink,
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: deepLink));
                            _showCopied(context);
                          },
                          child: const Icon(LucideIcons.copy, size: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionBtn(
                          label: "Copy Link",
                          icon: LucideIcons.copy,
                          color: Colors.grey.shade700,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: deepLink));
                            _showCopied(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionBtn(
                          label: "Share",
                          icon: LucideIcons.share2,
                          color: Colors.black,
                          onTap: () => _shareLink(churchName, inviteCode, deepLink),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── 2. QR Code Card ──────────────────────────────
            _InviteCard(
              icon: LucideIcons.qrCode,
              title: "QR Code",
              subtitle: "Scan with phone camera to join",
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrCodeWithLogo(data: deepLink, size: 180),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Members can scan this with their phone camera to open the join page directly.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── 3. Quick Share Card ──────────────────────────────
            _InviteCard(
              icon: LucideIcons.messageCircle,
              title: "Quick Share",
              subtitle: "Send via your favorite app",
              child: Row(
                children: [
                  Expanded(
                    child: _QuickShareBtn(
                      label: "WhatsApp",
                      icon: Icons.chat,
                      color: const Color(0xFF25D366),
                      onTap: () => _shareWhatsApp(churchName, inviteCode, deepLink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickShareBtn(
                      label: "SMS",
                      icon: LucideIcons.messageSquare,
                      color: const Color(0xFF2196F3),
                      onTap: () => _shareSMS(churchName, inviteCode, deepLink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickShareBtn(
                      label: "More...",
                      icon: LucideIcons.moreHorizontal,
                      color: Colors.grey.shade600,
                      onTap: () => _shareLink(churchName, inviteCode, deepLink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── 4. Invite Code Card ──────────────────────────────
            _InviteCard(
              icon: LucideIcons.key,
              title: "Invite Code",
              subtitle: "Members can enter this manually in the app",
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      inviteCode,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: inviteCode));
                        _showCopied(context);
                      },
                      icon: const Icon(LucideIcons.copy, size: 16),
                      label: const Text("Copy Code"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── How It Works ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("How members join:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  _HowStep(step: "1", text: "Download Church On App from Play Store / App Store"),
                  _HowStep(step: "2", text: "Open the app and sign up (or sign in)"),
                  _HowStep(step: "3", text: "Tap 'Join Church' and enter the invite code or scan QR"),
                  _HowStep(step: "4", text: "Done! They're now a member of $churchName"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCopied(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Copied!"), backgroundColor: Colors.teal, duration: Duration(seconds: 1)),
    );
  }

  void _shareLink(String churchName, String code, String deepLink) {
    SharePlus.instance.share(ShareParams(
      text: "Join $churchName on Church On App!\n\n"
          "Use invite code: $code\n"
          "Or tap this link: $deepLink\n\n"
          "Download the app: https://churchonapp.com",
    ));
  }

  void _shareWhatsApp(String churchName, String code, String deepLink) async {
    final message = Uri.encodeComponent(
      "Join $churchName on Church On App!\n\n"
      "Use invite code: $code\n"
      "Or tap this link: $deepLink\n\n"
      "Download the app: https://churchonapp.com",
    );
    final url = Uri.parse("https://wa.me/?text=$message");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _shareSMS(String churchName, String code, String deepLink) async {
    final message = Uri.encodeComponent(
      "Join $churchName on Church On App!\nUse invite code: $code\nOr tap: $deepLink",
    );
    final url = Uri.parse("sms:?body=$message");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

// ─── Private Widgets ──────────────────────────────────────────

class _InviteCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _InviteCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.amber.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _QuickShareBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickShareBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

class _HowStep extends StatelessWidget {
  final String step;
  final String text;

  const _HowStep({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.blue.shade600,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }
}
