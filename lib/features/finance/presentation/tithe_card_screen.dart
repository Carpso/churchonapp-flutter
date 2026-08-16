import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/rendering.dart';
import 'package:universal_io/io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:shimmer/shimmer.dart';
import '../data/finance_providers.dart';
import '../data/tithe_models.dart';

class TitheCardScreen extends ConsumerStatefulWidget {
  const TitheCardScreen({super.key});

  @override
  ConsumerState<TitheCardScreen> createState() => _TitheCardScreenState();
}

class _TitheCardScreenState extends ConsumerState<TitheCardScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isDownloading = false;

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final titheCardAsync = ref.watch(currentTitheCardProvider);
    ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Digital Tithe Card", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.canPop() ? Navigator.pop(context) : context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.share2),
            onPressed: _isDownloading ? null : _shareCard,
            tooltip: 'Share Card',
          ),
          IconButton(
            icon: const Icon(LucideIcons.download),
            onPressed: _isDownloading ? null : _downloadCard,
            tooltip: 'Download Card',
          ),
        ],
      ),
      body: titheCardAsync.when(
        data: (card) => _buildContent(context, tenant, card),
        loading: () => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Column(
              children: [
                Container(width: double.infinity, height: 280, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28))),
                const SizedBox(height: 24),
                Container(width: double.infinity, height: 200, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28))),
                const SizedBox(height: 24),
                Container(width: double.infinity, height: 180, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28))),
                const SizedBox(height: 24),
                Container(width: double.infinity, height: 60, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
                const SizedBox(height: 12),
                Container(width: double.infinity, height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
              ],
            ),
          ),
        ),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.alertCircle, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text("Could not load tithe card", style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Text("$e", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => ref.invalidate(currentTitheCardProvider),
                  child: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Tenant? tenant, TitheCard? card) {
    if (card == null || tenant == null) {
      return _buildEmptyState(context, tenant);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildDigitalCard(context, tenant, card),
          const SizedBox(height: 24),
          _buildStatsSection(card),
          const SizedBox(height: 24),
          _buildRecentTithes(card),
          const SizedBox(height: 24),
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, Tenant? tenant) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.creditCard, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              "No Tithe Card Yet",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              "Start your tithing journey to unlock your digital tithe card.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/giving'),
              icon: const Icon(LucideIcons.gift),
              label: const Text("Give Tithe"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.black,
                minimumSize: const Size(200, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDigitalCard(BuildContext context, Tenant? tenant, TitheCard? card) {
    final primaryColor = tenant?.primaryColor ?? const Color(0xFFFFD700);
    final accentColor = tenant?.accentColor ?? const Color(0xFF1A1A1A);
    final profileValue = ref.watch(profileProvider).value;
    final memberName = card?.memberName ?? (profileValue?.name ?? 'Believer');
    final memberId = card?.memberId ?? 'CHN-2024-0001';
    final memberEmail = card?.memberEmail;
    final memberPhone = card?.memberPhone ?? profileValue?.phoneNumber;
    final churchName = tenant?.name ?? 'Church On App';
    final logoUrl = tenant?.logoUrl;
    final qrData = 'coa://tithe/${tenant?.id ?? 'church'}/$memberId';

    return RepaintBoundary(
      key: _cardKey,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryColor, const Color(0xFFFFB300), accentColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFB300).withValues(alpha: 0.4),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (logoUrl != null)
                        AppImage(logoUrl, height: 32, width: 32, fit: BoxFit.cover, borderRadius: BorderRadius.circular(8)),
                      if (logoUrl != null) const SizedBox(height: 8),
                      Text(
                        churchName,
                        style: TextStyle(
                          color: primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.shield, size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        "DIGITAL TITHE CARD",
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              memberId,
              style: TextStyle(
                color: primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              memberName,
              style: TextStyle(
                color: primaryColor.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (memberEmail != null || memberPhone != null) ...[
              const SizedBox(height: 4),
              Text(
                memberEmail ?? memberPhone ?? '',
                style: TextStyle(
                  color: primaryColor.computeLuminance() > 0.5 ? Colors.black45 : Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "LIFETIME TITHES",
                      style: TextStyle(
                        color: primaryColor.computeLuminance() > 0.5 ? Colors.black54 : Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "K ${(card?.totalTitheAmount ?? 0).toStringAsFixed(0)}",
                      style: TextStyle(
                        color: primaryColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 72,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(TitheCard? card) {
    if (card == null) return const SizedBox.shrink();

    final totalTithe = card.totalTitheAmount;
    final titheCount = card.titheCount;
    final lastDate = card.lastTitheDate;
    final frequency = card.frequency;
    final avgTithe = titheCount > 0 ? totalTithe / titheCount : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.barChart3, color: Theme.of(context).primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                "YOUR TITHING STATS",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _statBuilder("Lifetime Total", "K ${totalTithe.toStringAsFixed(2)}", Theme.of(context).primaryColor),
              const SizedBox(width: 16),
              _statBuilder("Times Tithed", "$titheCount", Theme.of(context).primaryColor.withValues(alpha: 0.7)),
              const SizedBox(width: 16),
              _statBuilder("Avg. Tithe", "K ${avgTithe.toStringAsFixed(0)}", Colors.green),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(LucideIcons.calendar, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text(
                "Last Tithe: ${DateFormat.yMMMd().format(lastDate)}",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _frequencyColor(frequency).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  frequency.toUpperCase(),
                  style: TextStyle(
                    color: _frequencyColor(frequency),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: titheCount > 0 ? (titheCount % 52) / 52.0 : 0,
              backgroundColor: Colors.grey.shade200,
              color: Theme.of(context).primaryColor,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Annual Tithing Progress (${titheCount % 52} of 52 weeks)",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _statBuilder(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Color _frequencyColor(String frequency) {
    final brand = Theme.of(context).primaryColor;
    switch (frequency) {
      case 'weekly':
        return Colors.green;
      case 'monthly':
        return brand;
      default:
        return brand.withValues(alpha: 0.7);
    }
  }

  Widget _buildRecentTithes(TitheCard? card) {
    if (card == null || card.recentTithes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.clock, size: 20, color: Theme.of(context).primaryColor),
                ),
                const SizedBox(width: 12),
                const Text("RECENT TITHES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ],
            ),
            TextButton(
              onPressed: () => context.push('/tithe-history'),
              child: Text("View All", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
            ),
            ],
          ),
          const SizedBox(height: 16),
          ...card.recentTithes.take(5).map((record) => _buildTitheRecord(record)),
        ],
      ),
    );
  }

  Widget _buildTitheRecord(TitheRecord record) {
    final isConfirmed = record.status == 'confirmed';
    final IconData methodIcon;
    switch (record.paymentMethod) {
      case 'card':
        methodIcon = LucideIcons.creditCard;
        break;
      case 'cash':
        methodIcon = LucideIcons.banknote;
        break;
      default:
        methodIcon = LucideIcons.smartphone;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(methodIcon, size: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.yMMMd().format(record.date),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  record.paymentMethod ?? 'Mobile Money',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "K ${record.amount.toStringAsFixed(2)}",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Theme.of(context).primaryColor),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isConfirmed ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isConfirmed ? "Confirmed" : "Pending",
                  style: TextStyle(
                    color: isConfirmed ? Colors.green : Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: () => context.push('/giving'),
          icon: Icon(LucideIcons.gift, color: Colors.black),
          label: const Text(
            "Give Tithe Now",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 4,
            shadowColor: Theme.of(context).primaryColor.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.push('/tithe-history'),
          icon: const Icon(LucideIcons.list, size: 18),
          label: const Text("View Full History", style: TextStyle(fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).primaryColor,
            side: BorderSide(color: Theme.of(context).primaryColor),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Future<void> _downloadCard() async {
    setState(() => _isDownloading = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/tithe_card.png');
      await file.writeAsBytes(pngBytes);
      if (mounted) PremiumToast.showSuccess(context, "Tithe card saved to gallery", title: "Downloaded");
    } catch (e) {
      if (mounted) PremiumToast.showError(context, "Failed to download card: $e");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _shareCard() async {
    setState(() => _isDownloading = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tithe_card.png');
      await file.writeAsBytes(pngBytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: "My Digital Tithe Card - Church On App"));
    } catch (e) {
      if (mounted) PremiumToast.showError(context, "Failed to share: $e");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }
}