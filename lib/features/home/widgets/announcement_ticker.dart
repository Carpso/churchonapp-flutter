import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/admin/data/reporting_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class AnnouncementTicker extends ConsumerWidget {
  const AnnouncementTicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    if (tenant == null) return const SizedBox.shrink();

    final reportsAsync = ref.watch(reportsStreamProvider(tenant.id));

    return reportsAsync.when(
      data: (reports) {
        final profile = ref.watch(profileProvider).value;
        final isLeadership = profile?.isLeadershipTeam ?? false;

        final announcements = reports.where((r) {
          if (r.type == 'announcement') return true;
          if (r.type == 'private_memo' && isLeadership) return true;
          return false;
        }).toList();

        if (announcements.isEmpty) {
          return const _StaticTicker(text: "Welcome to Church On App! Stay tuned for live updates and announcements.");
        }

        final tickerText = announcements.map((a) {
          final prefix = a.type == 'private_memo' ? "🔒 BISHOP'S MEMO: " : "📣 ";
          return "$prefix ${a.title}: ${a.description}";
        }).join("   •   ");
        
        return _StaticTicker(
          text: tickerText, 
          isPrivate: announcements.any((a) => a.type == 'private_memo'),
        );
      },
      loading: () => const _StaticTicker(text: "Syncing announcements..."),
      error: (e, _) => _StaticTicker(text: "Connect with us! God bless your week."),
    );
  }
}

class _StaticTicker extends StatefulWidget {
  final String text;
  final bool isPrivate;
  const _StaticTicker({required this.text, this.isPrivate = false});

  @override
  State<_StaticTicker> createState() => _StaticTickerState();
}

class _StaticTickerState extends State<_StaticTicker> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _controller;
  double _accumulated = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Game-loop driven scroll: advance ~1px per 50ms of animation time. The
    // controller only ticks while the widget is on screen, so we never burn
    // cycles in an endless while-loop when the home tab is idle/backgrounded.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    );
    _controller.addListener(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.repeat());
  }

  void _onTick() {
    if (!mounted || !_scrollController.hasClients) return;
    _accumulated += 1;
    // ~20 ticks/second => ~1px per tick.
    if (_accumulated < 1) return;
    _accumulated = _accumulated % 1;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent) {
      _scrollController.jumpTo(0);
    } else {
      _scrollController.jumpTo(position.pixels + 1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.isPrivate ? Colors.amber.withValues(alpha: 0.1) : Theme.of(context).primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: widget.isPrivate ? Colors.amber.withValues(alpha: 0.3) : Theme.of(context).primaryColor.withValues(alpha: 0.1)),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            widget.text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

