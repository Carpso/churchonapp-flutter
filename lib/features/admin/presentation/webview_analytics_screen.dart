import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/services/webview_analytics_service.dart';

/// COA view of what external links members actually open in the in-app browser.
///
/// Backed by `get_webview_analytics(days, limit)` (SECURITY DEFINER, staff-only)
/// over the `webview_opens` table.
class WebviewAnalyticsScreen extends ConsumerStatefulWidget {
  const WebviewAnalyticsScreen({super.key});

  @override
  ConsumerState<WebviewAnalyticsScreen> createState() =>
      _WebviewAnalyticsScreenState();
}

class _WebviewAnalyticsScreenState
    extends ConsumerState<WebviewAnalyticsScreen> {
  int _days = 30;
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await ref
        .read(webviewAnalyticsProvider)
        .topOpened(days: _days, limit: 50);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalOpens = _rows.fold<int>(
        0, (a, r) => a + ((r['opens'] as num?)?.toInt() ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('In-App Browser Analytics'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Window selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                for (final d in const [7, 30, 90])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${d}d'),
                      selected: _days == d,
                      onSelected: (_) {
                        setState(() => _days = d);
                        _load();
                      },
                    ),
                  ),
                const Spacer(),
                Text('$totalOpens opens',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.globe,
                                  size: 44, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No external links opened in the last $_days days.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final r = _rows[i];
                            final url = (r['url'] ?? '').toString();
                            final source = (r['source'] ?? '').toString();
                            final opens = (r['opens'] as num?)?.toInt() ?? 0;
                            final users =
                                (r['unique_users'] as num?)?.toInt() ?? 0;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.primaryColor.withValues(alpha: 0.15),
                                child: Text('${i + 1}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: theme.primaryColor)),
                              ),
                              title: Text(
                                url,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              subtitle: Text(
                                '${source.isEmpty ? 'unknown' : source} · $opens opens · $users users',
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
