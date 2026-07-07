import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/devotion_service.dart';
import 'devotion_detail_screen.dart';

class DailyDevotionsScreen extends ConsumerStatefulWidget {
  const DailyDevotionsScreen({super.key});

  @override
  ConsumerState<DailyDevotionsScreen> createState() => _DailyDevotionsScreenState();
}

class _DailyDevotionsScreenState extends ConsumerState<DailyDevotionsScreen> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final devotionsAsync = ref.watch(devotionsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('Daily Devotions'),
      ),
      body: devotionsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.amber),
        ),
        error: (e, s) => Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.wifiOff, size: 40, color: Colors.grey),
                const SizedBox(height: 10),
                const Text(
                  'Failed to load devotions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 5),
                Text(
                  '$e',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 15),
                ElevatedButton(
                  onPressed: () => ref.invalidate(devotionsProvider),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  child: const Text('RETRY', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        data: (devotions) {
          final todayDevotion = devotions.isNotEmpty && devotions.first.isToday
              ? devotions.first
              : null;
          final pastDevotions = todayDevotion != null
              ? devotions.sublist(1)
              : devotions;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(devotionsProvider);
              await ref.read(devotionsProvider.future);
            },
            color: Colors.amber,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                if (todayDevotion != null) ...[
                  _buildTodayCard(todayDevotion),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Icon(LucideIcons.clock, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        'Past Devotions',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                ...pastDevotions.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildPastDevotionCard(d),
                )),
                if (pastDevotions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(LucideIcons.bookOpen, size: 40, color: Colors.grey[300]),
                          const SizedBox(height: 10),
                          Text(
                            'No devotions yet',
                            style: TextStyle(color: Colors.grey[500], fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTodayCard(Devotion devotion) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DevotionDetailScreen(devotion: devotion)),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.25), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.sparkles, size: 12, color: Colors.amber),
                        SizedBox(width: 5),
                        Text(
                          'Today\'s Devotion',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    devotion.formattedDate,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                devotion.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3436),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                devotion.reference,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _expanded
                    ? (devotion.scriptureText.isNotEmpty
                        ? '${devotion.scriptureText}\n\n${devotion.reflection}'
                        : devotion.reflection)
                    : devotion.excerpt,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF636E72),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      if (_expanded) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DevotionDetailScreen(devotion: devotion),
                          ),
                        );
                      } else {
                        setState(() => _expanded = !_expanded);
                      }
                    },
                    icon: Icon(
                      _expanded ? LucideIcons.chevronRight : LucideIcons.chevronDown,
                      size: 16,
                      color: Colors.amber,
                    ),
                    label: Text(
                      _expanded ? 'Full Detail' : 'Read More',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  ),
                  Row(
                    children: [
                      Icon(LucideIcons.bookOpen, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        devotion.reference,
                        style: TextStyle(color: Colors.grey[400], fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPastDevotionCard(Devotion devotion) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DevotionDetailScreen(devotion: devotion)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.bookOpen, size: 20, color: Colors.amber),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      devotion.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D3436),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(LucideIcons.calendar, size: 11, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          devotion.formattedDate,
                          style: TextStyle(color: Colors.grey[400], fontSize: 11),
                        ),
                        const SizedBox(width: 10),
                        Icon(LucideIcons.bookOpen, size: 11, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          devotion.reference,
                          style: TextStyle(color: Colors.grey[400], fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: Colors.grey[300]),
            ],
          ),
        ),
      ),
    );
  }
}
