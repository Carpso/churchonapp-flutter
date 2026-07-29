import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/admin/data/ad_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/widgets/app_image.dart';

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
              launchUrl(Uri.parse(ad.targetUrl!), mode: LaunchMode.inAppWebView);
            }
          },
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 80,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (ad.imageUrl != null)
                    AppImage(ad.imageUrl!, fit: BoxFit.cover)
                  else
                    Container(color: Colors.grey[900]),
                  Container(color: Colors.black.withValues(alpha: 0.4)),
                  Center(
                    child: Text(
                      ad.title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
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
