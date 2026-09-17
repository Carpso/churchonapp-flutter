import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/features/modules/bible_quiz/data/achievement_service.dart';
import 'package:shimmer/shimmer.dart';

class Certificate {
  final String id;
  final String title;
  final String description;
  final String category;
  final String icon;
  final DateTime? earnedAt;

  /// The issuing tenant's id, when the certificate belongs to a specific
  /// church (e.g. a baptism recorded for that church). `null` (and anything
  /// that does not match the current tenant) means the certificate was issued
  /// by Church On App itself.
  final String? tenantId;

  Certificate({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.icon,
    this.earnedAt,
    this.tenantId,
  });
}

/// Resolved branding for a certificate: COA (sunflower yellow + dark accent,
/// app logo) or tenant (the church's own theme colours + church logo).
class CertificateBrand {
  final Color primary;
  final Color accent;
  final String? logoUrl;
  final String issuerName;
  final bool tenantIssued;

  const CertificateBrand({
    required this.primary,
    required this.accent,
    required this.logoUrl,
    required this.issuerName,
    required this.tenantIssued,
  });
}

CertificateBrand certificateBrandFor(Certificate cert, Tenant? tenant) {
  final id = cert.tenantId;
  final isTenant = id != null && id.isNotEmpty && tenant != null && tenant.id == id;
  if (isTenant) {
    return CertificateBrand(
      primary: tenant.primaryColor,
      accent: tenant.accentColor,
      logoUrl: tenant.logoUrl,
      issuerName: tenant.name,
      tenantIssued: true,
    );
  }
  return const CertificateBrand(
    primary: AppConstants.sunflowerYellow,
    accent: AppConstants.primaryDark,
    logoUrl: null,
    issuerName: 'Church On App',
    tenantIssued: false,
  );
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
        .select('id, name, date, minister, location, created_at, tenant_id')
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
        tenantId: b['tenant_id']?.toString(),
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
    final tenant = ref.watch(currentTenantProvider);
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
          final userName = ref.watch(profileProvider).value?.name ?? 'Believer';

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
                    ...categoryCerts.map((cert) => _CertificateCard(
                          cert: cert,
                          userName: userName,
                          brand: certificateBrandFor(cert, tenant),
                        )),
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

/// Foreground colour that stays readable on top of [background].
Color _onBrand(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : AppConstants.primaryDark;

/// Issuer logo: the tenant church logo when available, otherwise the bundled
/// Church On App logo. Both degrade to a brand-tinted icon.
class _BrandLogo extends StatelessWidget {
  final CertificateBrand brand;
  final double size;

  const _BrandLogo({required this.brand, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final url = brand.logoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return AppImage(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        borderRadius: BorderRadius.circular(size * 0.28),
        errorWidget: (_, __) => _fallback(context),
      );
    }

    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Image.asset(
      'assets/app_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: px,
      cacheHeight: px,
      errorBuilder: (_, __, ___) => _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brand.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        brand.tenantIssued ? Icons.church : LucideIcons.award,
        size: size * 0.55,
        color: brand.accent,
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  final Certificate cert;
  final String userName;
  final CertificateBrand brand;

  const _CertificateCard({
    required this.cert,
    required this.userName,
    required this.brand,
  });

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

  /// Loads the issuer logo bytes for the PDF: the tenant logo when present,
  /// otherwise the bundled Church On App logo. Returns null on failure.
  Future<pw.MemoryImage?> _loadPdfLogo() async {
    final url = brand.logoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      try {
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          return pw.MemoryImage(res.bodyBytes);
        }
      } catch (e) {
        debugPrint('Certificate PDF logo fetch failed (non-fatal): $e');
      }
    }
    try {
      final data = await rootBundle.load('assets/app_logo.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      debugPrint('Certificate PDF asset logo failed (non-fatal): $e');
      return null;
    }
  }

  Future<Uint8List> _buildPdf() async {
    final pdf = pw.Document();
    final color = brand.primary;
    final logo = await _loadPdfLogo();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              if (logo != null) ...[
                pw.Center(child: pw.Image(logo, width: 90, height: 90)),
                pw.SizedBox(height: 20),
              ] else
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
                userName,
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
                '${brand.issuerName} - Digital Certificate',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey400),
              ),
              pw.Text(
                brand.tenantIssued
                    ? 'Issued via Church On App - churchonapp.com'
                    : 'Verified at churchonapp.com',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey400),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<String> _generatePdfFile() async {
    final bytes = await _buildPdf();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/certificate_${cert.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _sharePdf() async {
    final path = await _generatePdfFile();
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: '${cert.title} - ${brand.issuerName}'));
  }

  Future<void> _showDetail(BuildContext context) {
    final categoryColor = _categoryColor(cert.category);
    final onPrimary = _onBrand(brand.primary);

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
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: brand.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: brand.primary.withValues(alpha: 0.35)),
                ),
                child: _BrandLogo(brand: brand, size: 56),
              ),
              const SizedBox(height: 16),
              Text(cert.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(cert.description, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.4)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: brand.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(brand.tenantIssued ? Icons.church : LucideIcons.award, size: 14, color: brand.accent),
                    const SizedBox(width: 6),
                    Text(
                      brand.issuerName,
                      style: TextStyle(color: brand.accent, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_resolveIcon(cert.icon), size: 14, color: categoryColor),
                      const SizedBox(width: 4),
                      Text(cert.category, style: TextStyle(color: categoryColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (cert.earnedAt != null)
                    Text('Earned ${DateFormat.yMMMd().format(cert.earnedAt!)}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _sharePdf();
                      },
                      icon: const Icon(LucideIcons.share2, size: 18),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: brand.accent,
                        side: BorderSide(color: brand.primary.withValues(alpha: 0.6)),
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
                        final path = await _generatePdfFile();
                        await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: '${cert.title} - ${brand.issuerName}'));
                      },
                      icon: const Icon(LucideIcons.download, size: 18),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brand.primary,
                        foregroundColor: onPrimary,
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
    final categoryColor = _categoryColor(cert.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showDetail(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: brand.primary.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: brand.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _BrandLogo(brand: brand, size: 34),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cert.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(cert.description, style: TextStyle(color: Colors.grey.shade600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            brand.tenantIssued ? Icons.church : LucideIcons.award,
                            size: 12,
                            color: brand.accent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              brand.issuerName,
                              style: TextStyle(color: brand.accent, fontSize: 11, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 4, height: 4, decoration: BoxDecoration(color: categoryColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(cert.category, style: TextStyle(color: categoryColor, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (cert.earnedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          DateFormat.yMMMd().format(cert.earnedAt!),
                          style: TextStyle(color: brand.accent.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, color: brand.accent.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
