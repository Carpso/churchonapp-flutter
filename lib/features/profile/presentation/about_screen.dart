import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(LucideIcons.arrowLeft, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("About", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(LucideIcons.church, color: Colors.amber, size: 64),
            ),
            const SizedBox(height: 24),
            const Text("Church On App", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Version 1.0.0+40", style: TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 24),
            Text(
              "Church On App is a comprehensive church management and community platform. "
              "It connects congregations, facilitates giving, manages events, and provides transportation services through Carpso Ride. "
              "Built with love for the global Church.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 40),
            _infoRow(LucideIcons.globe, "Website", "churchonapp.com", () async {
              final url = Uri.parse("https://churchonapp.com");
              if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.inAppWebView);
            }),
            _infoRow(LucideIcons.mail, "Email", "hello@churchonapp.com", () async {
              final url = Uri.parse("mailto:hello@churchonapp.com");
              if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.inAppWebView);
            }),
            _infoRow(LucideIcons.phone, "Phone", "+260 968 551 110", () async {
              final url = Uri.parse("tel:+260968551110");
              if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.inAppWebView);
            }),
            _infoRow(LucideIcons.mapPin, "Location", "Lusaka, Zambia", null),
            const SizedBox(height: 40),
            Text(
              "© 2026 Church On App Global. Powered by Carpso Solutions.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.amber, size: 20),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
            const Spacer(),
            if (onTap != null) const Icon(LucideIcons.externalLink, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}
