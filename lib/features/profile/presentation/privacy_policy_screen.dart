import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(LucideIcons.arrowLeft, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("Privacy Policy", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section("1. Information We Collect",
              "We collect information you provide when creating an account, including your name, email address, phone number, and church affiliation. "
              "When you use Carpso Ride, we collect location data and trip history. "
              "When you submit KYC documents (NRC, Passport, Driver's License), these are encrypted before storage."),
            _section("2. How We Use Your Information",
              "Your information is used to provide and improve our services, process transactions, "
              "verify your identity for security purposes, and communicate with you about platform updates."),
            _section("3. Data Encryption & Security",
              "All sensitive documents (NRC, Passports, ID cards) are encrypted using AES-256-CBC encryption before being stored. "
              "Data in transit is protected by TLS 1.3. Payment information is processed through Lipila's secure payment gateway. "
              "2FA (Two-Factor Authentication) is available for all accounts."),
            _section("4. Data Sharing",
              "We do not sell your personal data. Information may be shared with your church administration "
              "for membership verification and with payment processors for transaction processing."),
            _section("5. Your Rights",
              "You may request access to, correction of, or deletion of your personal data at any time by contacting our support team. "
              "You can enable or disable 2FA from your Security & Privacy settings."),
            _section("6. Data Retention",
              "We retain your account data for as long as your account is active. KYC documents are retained for 5 years "
              "after account closure for regulatory compliance purposes."),
            _section("7. Contact",
              "For privacy-related inquiries, contact us at hello@churchonapp.com or call +260 968 551 110."),
            const SizedBox(height: 20),
            Center(
              child: Text("Last updated: July 2026", style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.shield, color: Colors.amber, size: 18),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}
