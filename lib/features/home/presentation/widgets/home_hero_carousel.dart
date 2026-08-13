import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/church/data/church_schedule_service.dart';
import 'package:church_on_app/features/church/data/church_service_time.dart';
import 'package:church_on_app/features/navigation/presentation/carpso_service_ride_card.dart';
import 'home_hero_card.dart';

/// Hero carousel that shows the church card plus dynamic Carpso Ride cards
/// for any services scheduled for the current day.
class HomeHeroCarousel extends ConsumerStatefulWidget {
  const HomeHeroCarousel({super.key});

  @override
  ConsumerState<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends ConsumerState<HomeHeroCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final page = _controller.page?.round() ?? 0;
      if (page != _currentPage && mounted) {
        setState(() => _currentPage = page);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _dayName(int weekday) {
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names[weekday - 1];
  }

  static String _twentyFourHour(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    AsyncValue<List<ChurchServiceTime>> todayServicesAsync;
    if (tenant != null) {
      todayServicesAsync = ref.watch(todaysChurchServicesProvider(tenant.id));
    } else {
      todayServicesAsync = const AsyncData(<ChurchServiceTime>[]);
    }

    return todayServicesAsync.when(
      data: (services) {
        final carpsoEnabled = widgetRemoteConfig(ref).getBool('carpso_ride_enabled', true);
        final carpsoServices = carpsoEnabled
            ? services.where((s) => s.enableCarpso).toList()
            : <ChurchServiceTime>[];
        final pages = <Widget>[const HomeHeroCard()];
        final now = DateTime.now();
        for (final s in carpsoServices) {
          pages.add(
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: CarpsoServiceRideCard(
                title: 'Book a ride to ${s.title}',
                subtitle: '${_dayName(now.weekday)} ${s.title} at ${_twentyFourHour(s.startTime)}.'
                    ' Tap to book your Carpso Ride now.',
                showButton: true,
              ),
            ),
          );
        }

        if (pages.length == 1) {
          return const HomeHeroCard();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 245,
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: pages[index],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pages.length, (index) {
                final active = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? Theme.of(context).primaryColor : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        );
      },
      loading: () => const HomeHeroCard(),
      error: (_, __) => const HomeHeroCard(),
    );
  }
}
