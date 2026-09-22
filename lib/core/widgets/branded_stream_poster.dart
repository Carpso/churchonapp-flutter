import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/config/sample_posters.dart';
import 'package:church_on_app/core/widgets/app_image.dart';

/// The branded poster compositions used as the default art for streams,
/// sermons and klips that have no custom image.
///
/// These are drawn entirely in Flutter (logo + brand gradient + text) so they
/// stay on-brand and never depend on third-party stock photography.
enum BrandedPosterVariant {
  sundayService(
    label: 'Sunday Service',
    tagline: 'Live on Church On App',
    icon: LucideIcons.church,
  ),
  bibleStudy(
    label: 'Bible Study',
    tagline: 'Grow in the Word on Church On App',
    icon: LucideIcons.bookOpen,
  ),
  prayerMeeting(
    label: 'Prayer Meeting',
    tagline: 'United in prayer on Church On App',
    icon: LucideIcons.heartHandshake,
  ),
  youthService(
    label: 'Youth Service',
    tagline: 'Raising a generation on Church On App',
    icon: LucideIcons.users,
  ),
  specialGuest(
    label: 'Special Guest',
    tagline: 'Anointed ministry on Church On App',
    icon: LucideIcons.mic2,
  ),
  revivalNight(
    label: 'Revival Night',
    tagline: 'Fire from heaven on Church On App',
    icon: LucideIcons.flame,
  );

  const BrandedPosterVariant({
    required this.label,
    required this.tagline,
    required this.icon,
  });

  final String label;
  final String tagline;
  final IconData icon;
}

/// Stable variant for a given seed so a stream/sermon always shows the same
/// branded poster across rebuilds.
BrandedPosterVariant brandedPosterVariantFor(Object seed) {
  final s = seed.toString();
  if (s.isEmpty) return BrandedPosterVariant.sundayService;
  var hash = 0;
  for (final unit in s.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return BrandedPosterVariant.values[hash % BrandedPosterVariant.values.length];
}

/// The Church On App logo mark, sized for small poster/placeholder slots.
class BrandLogoMark extends StatelessWidget {
  const BrandLogoMark({super.key, this.size = 48, this.padding = 8});

  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        AppConstants.logoAsset,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(LucideIcons.church, color: AppConstants.primaryDark),
      ),
    );
  }
}

/// A self-sizing, fully Flutter-drawn branded poster. Scales from tiny list
/// thumbnails (logo only) up to full-width hero posters (logo + title +
/// tagline). Never empty — always produces brand art.
class BrandedStreamPoster extends StatelessWidget {
  const BrandedStreamPoster({
    super.key,
    this.variant,
    this.seed = '',
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final BrandedPosterVariant? variant;
  final Object seed;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final v = variant ?? brandedPosterVariantFor(seed);
    Widget poster = Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F0F0F),
            Color(0xFF1C1C1C),
            Color(0xFF2A2405),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Sunflower glow (brand accent).
          Positioned(
            top: -0.35,
            right: -0.25,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppConstants.sunflowerYellow.withValues(alpha: 0.45),
                      AppConstants.sunflowerYellow.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Faint diagonal brand stripes.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _BrandStripesPainter()),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxH = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : (height ?? 160);
              final maxW = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : (width ?? 280);
              final short = math.min(maxW, maxH);

              // Tiny tile (e.g. 64x44 list thumb): logo only.
              if (maxH < 60 || short < 56) {
                return Center(
                  child: BrandLogoMark(size: math.min(maxH * 0.72, maxW * 0.5)),
                );
              }

              final logoSize = (short * 0.34).clamp(28.0, 72.0);
              final showTagline = maxH >= 120 && maxW >= 170;

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BrandLogoMark(size: logoSize, padding: logoSize * 0.16),
                      SizedBox(height: (maxH * 0.06).clamp(4.0, 14.0)),
                      Flexible(
                        child: Text(
                          v.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                            height: 1.05,
                            fontSize: (short * 0.16).clamp(12.0, 26.0),
                          ),
                        ),
                      ),
                      if (showTagline) ...[
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            v.tagline,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppConstants.sunflowerYellow,
                              fontWeight: FontWeight.w600,
                              fontSize: (short * 0.075).clamp(9.0, 13.0),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );

    if (borderRadius != null) {
      poster = ClipRRect(borderRadius: borderRadius!, child: poster);
    }
    return poster;
  }
}

class _BrandStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.square;
    const gap = 46.0;
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A drop-in replacement for `AppImage(posterOrDefault(...))` that prefers the
/// branded Flutter-drawn poster whenever the row has no REAL custom poster.
///
/// "No real custom poster" covers both a NULL/empty URL and the legacy
/// generated Unsplash sample URLs seeded by `20261202_sample_stream_posters`,
/// so existing content instantly adopts the branded defaults while genuinely
/// uploaded thumbnails are still displayed untouched.
class SmartStreamPoster extends StatelessWidget {
  const SmartStreamPoster({
    super.key,
    this.url,
    this.seed = '',
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.variant,
  });

  final String? url;
  final Object seed;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final BrandedPosterVariant? variant;

  @override
  Widget build(BuildContext context) {
    final effective = posterOrDefault(url, seed: seed);
    final useBranded =
        effective.trim().isEmpty || isGeneratedSamplePoster(effective);

    final Widget branded = BrandedStreamPoster(
      variant: variant,
      seed: seed,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
    );
    if (useBranded) return branded;

    // A REAL uploaded URL that fails to decode (e.g. a dead/HTML Unsplash
    // sample URL returning `EncodingError`) must fall back to the branded
    // poster rather than a broken-image box.
    return AppImage(
      effective,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      errorWidget: (_, __) => branded,
    );
  }
}
