import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final generalContacts = [
      {'icon': LucideIcons.shield, 'name': 'Police', 'phone': '911', 'color': Colors.blue},
      {'icon': LucideIcons.plusCircle, 'name': 'Ambulance', 'phone': '992', 'color': Colors.red},
      {'icon': LucideIcons.flame, 'name': 'Fire', 'phone': '993', 'color': Colors.orange},
    ];

    final churchContacts = [
      {'icon': LucideIcons.phone, 'name': 'Church Office', 'phone': '+260 968 551 110', 'color': theme.primaryColor},
      {'icon': LucideIcons.user, 'name': 'Pastor On Call', 'phone': '+260 968 551 111', 'color': Colors.purple},
      {'icon': LucideIcons.messageCircle, 'name': 'Prayer Line', 'phone': '+260 968 551 112', 'color': Colors.teal},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSectionLabel('Emergency Services'),
          const SizedBox(height: 12),
          ...generalContacts.map((c) => _buildContactCard(context, c)),
          const SizedBox(height: 28),
          _buildSectionLabel('Church Contacts'),
          const SizedBox(height: 12),
          ...churchContacts.map((c) => _buildContactCard(context, c)),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.grey,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildContactCard(BuildContext context, Map<String, dynamic> contact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (contact['color'] as Color).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            contact['icon'] as IconData,
            color: contact['color'] as Color,
            size: 22,
          ),
        ),
        title: Text(
          contact['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          contact['phone'] as String,
          style: TextStyle(
            color: (contact['color'] as Color).withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (contact['color'] as Color).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(LucideIcons.phone, color: contact['color'] as Color, size: 18),
        ),
        onTap: () async {
          final uri = Uri.parse('tel:${contact['phone']}');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        },
      ),
    );
  }
}
