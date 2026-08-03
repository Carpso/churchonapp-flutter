import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/devotion_service.dart';

class DevotionDetailScreen extends ConsumerWidget {
  final Devotion devotion;

  const DevotionDetailScreen({super.key, required this.devotion});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Daily Devotion'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.share2),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: '${devotion.reference}\n\n${devotion.scriptureText}\n\n${devotion.reflection}',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard — ready to share!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Share',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (devotion.isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.sun, size: 14, color: Colors.amber),
                    SizedBox(width: 6),
                    Text(
                      "Today's Devotion",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Text(
              devotion.title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3436),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(LucideIcons.calendar, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  devotion.formattedDate,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(width: 16),
                const Icon(LucideIcons.bookOpen, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  devotion.reference,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (devotion.scriptureText.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.bookmark, size: 16, color: Colors.amber.shade700),
                        const SizedBox(width: 8),
                        Text(
                          devotion.reference,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      devotion.scriptureText,
                      style: const TextStyle(
                        fontSize: 17,
                        fontFamily: 'Georgia',
                        height: 1.7,
                        color: Color(0xFF2D3436),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            Text(
              'Reflection',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              devotion.reflection,
              style: const TextStyle(
                fontSize: 15,
                height: 1.7,
                color: Color(0xFF636E72),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.heart, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Prayer',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    devotion.prayer,
                    style: const TextStyle(
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                      height: 1.7,
                      color: Color(0xFF2D3436),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
