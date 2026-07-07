import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/admin/data/ad_service.dart';
import 'package:url_launcher/url_launcher.dart';

class AdBannerWidget extends ConsumerWidget {
  final String placement;

  const AdBannerWidget({super.key, this.placement = 'home'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adsAsync = ref.watch(activeAdsProvider(placement));

    return adsAsync.when(
      data: (ads) {
        if (ads.isEmpty) return const SizedBox.shrink();
        final ad = ads.first;
        return GestureDetector(
          onTap: () {
            ref.read(adServiceProvider).trackImpression(ad.id);
            if (ad.targetUrl != null) {
              launchUrl(Uri.parse(ad.targetUrl!), mode: LaunchMode.externalApplication);
            }
          },
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: ad.imageUrl != null
                    ? DecorationImage(image: NetworkImage(ad.imageUrl!), fit: BoxFit.cover)
                    : null,
                color: Colors.grey[900],
              ),
              alignment: Alignment.center,
              child: Text(
                ad.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
