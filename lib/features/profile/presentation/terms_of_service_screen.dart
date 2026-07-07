import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("Terms of Service", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section("1. Acceptance of Terms",
              "By accessing or using Church On App, Carpso Ride, and any associated services, you agree to be bound by these Terms. "
              "If you do not agree, do not use the platform."),
            _section("2. User Accounts",
              "You are responsible for maintaining the confidentiality of your account credentials. "
              "You must be at least 13 years old to use the platform. "
              "You agree to provide accurate and complete information during registration."),
            _section("3. Carpso Ride Services",
              "Carpso Ride connects riders with drivers for church-related transportation. "
              "All drivers undergo verification. Fares are calculated based on distance and displayed before ride confirmation. "
              "Users must treat drivers and fellow riders with respect."),
            _section("4. Payments & Fees",
              "Payments are processed through Lipila payment gateway. Platform fees apply to Carpso Ride transactions. "
              "Subscription fees for churches are billed according to the selected plan."),
            _section("5. User Conduct",
              "You agree not to misuse the platform for illegal activities, harassment, or fraudulent transactions. "
              "Violation may result in account suspension and legal action."),
            _section("6. KYC Verification",
              "Identity verification documents (NRC, Passport, etc.) are required for certain platform features. "
              "Documents are encrypted and stored securely. Failure to submit valid documents may restrict access to certain features."),
            _section("7. Limitation of Liability",
              "Church On App is not liable for disputes between users, drivers, and riders. "
              "The platform provides the connection service; individual service quality is the responsibility of the service provider."),
            _section("8. Termination",
              "We reserve the right to suspend or terminate accounts that violate these terms. "
              "Users may delete their accounts at any time from their profile settings."),
            _section("9. Changes to Terms",
              "We may update these terms at any time. Users will be notified of material changes via email or in-app notification."),
            _section("10. Contact",
              "For questions about these terms, contact hello@churchonapp.com or call +260 968 551 110."),
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
              const Icon(LucideIcons.scrollText, color: Colors.amber, size: 18),
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
