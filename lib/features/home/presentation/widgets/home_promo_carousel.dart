import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:church_on_app/features/home/data/special_offer_service.dart';
import 'package:church_on_app/features/marketplace/presentation/marketplace_screen.dart';
import 'package:church_on_app/core/widgets/app_image.dart';

/// DB-driven promotional carousel — renders the owner/team-managed
/// `special_offers` (promoted first). Hidden entirely when no offer is active.
class HomePromoCarousel extends ConsumerStatefulWidget {
  const HomePromoCarousel({super.key});

  @override
  ConsumerState<HomePromoCarousel> createState() => _HomePromoCarouselState();
}

class _HomePromoCarouselState extends ConsumerState<HomePromoCarousel> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offersAsync = ref.watch(activeSpecialOffersProvider);
    return offersAsync.when(
      data: (offers) {
        if (offers.isEmpty) return const SizedBox.shrink();
        final height = offers.length == 1 ? 160.0 : 176.0;
        return Column(
          children: [
            SizedBox(
              height: height,
              child: offers.length == 1
                  ? _PromoCard(offer: offers.first)
                  : PageView.builder(
                      controller: _controller,
                      itemCount: offers.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) =>
                          _PromoCard(offer: offers[i]),
                    ),
            ),
            if (offers.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(offers.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? Theme.of(context).primaryColor
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
    );
  }
}

class _PromoCard extends StatelessWidget {
  final SpecialOffer offer;
  const _PromoCard({required this.offer});

  Future<void> _onTap(BuildContext context) async {
    switch (offer.linkType) {
      case 'web':
        final target = offer.linkTarget;
        if (target != null && target.isNotEmpty) {
          await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
        }
        break;
      case 'none':
        break;
      case 'marketplace':
      default:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MarketplaceScreen(
              initialCategory: offer.linkTarget?.isNotEmpty == true
                  ? offer.linkTarget!
                  : "bookshop",
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = offer.imageUrl != null && offer.imageUrl!.isNotEmpty;
    final label = [offer.badge, offer.title, offer.subtitle]
        .where((t) => t != null && t.isNotEmpty)
        .join(' — ');
    return Semantics(
      button: true,
      label: label.isEmpty ? 'Promotion' : label,
      child: GestureDetector(
        onTap: () => _onTap(context),
        child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: theme.primaryColor.withValues(alpha: 0.2),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              AppImage(
                offer.imageUrl!,
                fit: BoxFit.cover,
                placeholder: _buildGradient(theme),
                errorWidget: (_, __) => _buildGradient(theme),
              )
            else
              _buildGradient(theme),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (offer.badge != null && offer.badge!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        offer.badge!,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    offer.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (offer.subtitle != null &&
                      offer.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      offer.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildGradient(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor,
            theme.primaryColor.withValues(alpha: 0.7),
            theme.primaryColor.withValues(alpha: 0.45),
          ],
        ),
      ),
    );
  }
}
