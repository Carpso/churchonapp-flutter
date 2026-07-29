import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/modules/bible_quiz/data/achievement_service.dart';
import 'package:shimmer/shimmer.dart';

class Certificate {
  final String id;
  final String title;
  final String description;
  final String category;
  final String icon;
  final DateTime? earnedAt;

  Certificate({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.icon,
    this.earnedAt,
  });
}

final certificatesProvider = FutureProvider<List<Certificate>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];

  final profile = ref.watch(profileProvider).value;
  final certs = <Certificate>[];

  try {
    final achievService = AchievementService();
    final achievements = await achievService.getUnlockedAchievements();

    for (final a in achievements) {
      if (a.isUnlocked) {
        certs.add(Certificate(
          id: a.id,
          title: a.title,
          description: a.description,
          category: 'Achievement',
          icon: a.icon,
          earnedAt: a.unlockedAt,
        ));
      }
    }
  } catch (e) {
    debugPrint('Error loading achievements: $e');
  }

  try {
    final baptisms = await Supabase.instance.client
        .from('baptisms')
        .select('id, name, date, minister, location, created_at')
        .eq('created_by', user.id)
        .order('date', ascending: false);

    for (final b in baptisms) {
      certs.add(Certificate(
        id: 'baptism_${b['id']}',
        title: 'Baptism Certificate',
        description: 'Baptized by ${b['minister'] ?? 'the church'} at ${b['location'] ?? 'the church'}',
        category: 'Baptism',
        icon: 'droplets',
        earnedAt: b['date'] != null ? DateTime.tryParse(b['date'].toString()) : null,
      ));
    }
  } catch (e) {
    debugPrint('Error loading baptisms: $e');
  }

  try {
    if (profile != null && profile.streakCount > 0) {
      certs.add(Certificate(
        id: 'streak_${profile.streakCount}',
        title: '${profile.streakCount}-Day Bible Reading Streak',
        description: 'Faithful daily Bible reading for ${profile.streakCount} consecutive days',
        category: 'Reading',
        icon: 'bookOpen',
        earnedAt: profile.lastReadAt,
      ));
    }
  } catch (e) {
    debugPrint('Error adding streak: $e');
  }

  certs.sort((a, b) {
    final aDate = a.earnedAt ?? DateTime(2000);
    final bDate = b.earnedAt ?? DateTime(2000);
    return bDate.compareTo(aDate);
  });

  return certs;
});

class CertificatesScreen extends ConsumerWidget {
  const CertificatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certsAsync = ref.watch(certificatesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Certificates'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: certsAsync.when(
        data: (certs) {
          if (certs.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(certificatesProvider),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.award, size: 80, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                        const SizedBox(height: 16),
                        Text('No certificates yet', style: TextStyle(fontSize: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                        const SizedBox(height: 8),
                        Text('Complete quizzes and activities to earn certificates', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3))),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          final categories = certs.map((c) => c.category).toSet().toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(certificatesProvider),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: categories.length,
              itemBuilder: (context, catIndex) {
              final category = categories[catIndex];
              final categoryCerts = certs.where((c) => c.category == category).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 16, bottom: 8),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  ...categoryCerts.map((cert) => _CertificateCard(cert: cert)),
                ],
              );
            },
          ),
        );
      },
      loading: () => Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade100,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox(width: double.infinity, height: 30, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(12))))),
              SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 80, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(16))))),
              SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 80, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(16))))),
              SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 80, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(16))))),
            ],
          ),
        ),
      ),
      error: (e, _) => Center(child: Text('Error loading certificates: $e')),
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  final Certificate cert;

  const _CertificateCard({required this.cert});

  Color _categoryColor(String category) {
    switch (category) {
      case 'Achievement':
        return const Color(0xFF8B5CF6);
      case 'Baptism':
        return const Color(0xFF06B6D4);
      case 'Reading':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  IconData _resolveIcon(String iconName) {
    switch (iconName) {
      case 'star':
        return LucideIcons.star;
      case 'trophy':
        return LucideIcons.trophy;
      case 'zap':
        return LucideIcons.zap;
      case 'flame':
        return LucideIcons.flame;
      case 'droplets':
        return LucideIcons.droplets;
      case 'bookOpen':
        return LucideIcons.bookOpen;
      case 'swords':
        return LucideIcons.swords;
      case 'shield':
        return LucideIcons.shield;
      case 'brain':
        return LucideIcons.brain;
      case 'heart':
        return LucideIcons.heart;
      case 'scroll':
        return LucideIcons.scrollText;
      case 'cross':
        return LucideIcons.cross;
      default:
        return LucideIcons.award;
    }
  }

  Future<Uint8List> _buildPdf(ThemeData theme) async {
    final pdf = pw.Document();
    final color = _categoryColor(cert.category);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.SizedBox(height: 60),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(color.withValues(alpha: 0.1).toARGB32()),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(60)),
                ),
                child: pw.Text(
                  'CERTIFICATE OF ACHIEVEMENT',
                  style: pw.TextStyle(
                    fontSize: 14,
                    letterSpacing: 3,
                    color: PdfColor.fromInt(color.toARGB32()),
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 40),
              pw.Text(
                'This is to certify that',
                style: pw.TextStyle(fontSize: 14, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Believer',
                style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'has successfully earned the',
                style: pw.TextStyle(fontSize: 14, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 24),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColor.fromInt(color.withValues(alpha: 0.5).toARGB32()), width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                ),
                child: pw.Text(
                      cert.title,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(color.toARGB32()),
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                cert.description,
                style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 12),
              if (cert.earnedAt != null)
                pw.Text(
                  'Awarded on ${DateFormat.yMMMMd().format(cert.earnedAt!)}',
                  style: pw.TextStyle(fontSize: 11, color: PdfColors.grey500),
                ),
              pw.SizedBox(height: 60),
              pw.Divider(),
              pw.SizedBox(height: 16),
              pw.Text(
                'Church On App - Digital Certificate',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey400),
              ),
              pw.Text(
                'Verified at churchonapp.com',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey400),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<String> _generatePdfFile(ThemeData theme) async {
    final bytes = await _buildPdf(theme);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/certificate_${cert.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _sharePdf(ThemeData theme) async {
    final path = await _generatePdfFile(theme);
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: '${cert.title} - Church On App'));
  }

  Future<void> _showDetail(BuildContext context, ThemeData theme) {
    final color = _categoryColor(cert.category);
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_resolveIcon(cert.icon), size: 48, color: color),
              ),
              const SizedBox(height: 20),
              Text(cert.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(cert.description, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.4)),
              const SizedBox(height: 12),
              Text(cert.category, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              if (cert.earnedAt != null) ...[
                const SizedBox(height: 4),
                Text('Earned ${DateFormat.yMMMd().format(cert.earnedAt!)}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _sharePdf(theme);
                      },
                      icon: const Icon(LucideIcons.share2, size: 18),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final path = await _generatePdfFile(theme);
                        await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: '${cert.title} - Church On App'));
                      },
                      icon: const Icon(LucideIcons.download, size: 18),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _categoryColor(cert.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showDetail(context, theme),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_resolveIcon(cert.icon), color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cert.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(cert.description, style: TextStyle(color: Colors.grey.shade600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (cert.earnedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(DateFormat.yMMMd().format(cert.earnedAt!), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, color: color.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
