import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'writers_studio_screen.dart';

class WriterDashboardScreen extends ConsumerStatefulWidget {
  const WriterDashboardScreen({super.key});

  @override
  ConsumerState<WriterDashboardScreen> createState() => _WriterDashboardScreenState();
}

class _WriterDashboardScreenState extends ConsumerState<WriterDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  int _publishedCount = 0;
  int _pendingCount = 0;
  int _totalSales = 0;
  int _booksListed = 0;
  List<Map<String, dynamic>> _myArticles = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    final userId = ref.read(profileProvider).value?.id;
    if (userId == null) { setState(() { _isLoading = false; _error = "Not logged in"; }); return; }

    try {
      // Articles live in `kingdom_news` (the writer studio publishes there).
      // `news_articles` / `marketplace_products` do not exist, so the previous
      // queries failed and this dashboard could never load.
      final articlesRes = await Supabase.instance.client
          .from('kingdom_news')
          .select('id, title, status, created_at')
          .eq('author_id', userId)
          .order('created_at', ascending: false);

      final articles = List<Map<String, dynamic>>.from(articlesRes);

      // Books a writer has listed, and units actually sold (order_items).
      int booksListed = 0;
      int sales = 0;
      try {
        final booksRes = await Supabase.instance.client
            .from('marketplace_items')
            .select('id')
            .eq('vendor_id', userId)
            .eq('category', 'bookshop');
        booksListed = (booksRes as List).length;

        final soldRes = await Supabase.instance.client
            .from('order_items')
            .select('quantity')
            .eq('vendor_id', userId);
        for (final row in (soldRes as List)) {
          sales += (row['quantity'] as num?)?.toInt() ?? 0;
        }
      } catch (e) {
        debugPrint('WriterDashboard: sales lookup failed (non-fatal): $e');
      }

      // Articles published before `status` was written have a NULL status and
      // are still live, so treat null/empty as published.
      bool isPublished(Map<String, dynamic> a) {
        final s = (a['status'] ?? '').toString().toLowerCase();
        return s.isEmpty || s == 'published';
      }

      final published = articles.where(isPublished).length;
      final pending = articles.length - published;

      if (mounted) {
        setState(() {
          _publishedCount = published; _pendingCount = pending;
          _totalSales = sales; _booksListed = booksListed;
          _myArticles = articles; _isLoading = false; _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Writer Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, foregroundColor: Colors.black87, elevation: 0,
        actions: [
          IconButton(icon: const Icon(LucideIcons.plus), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WriterStudioScreen())).then((_) => _loadDashboard())),
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadDashboard),
        ],
      ),
      body: _isLoading ? _buildShimmer() : _error != null ? _buildError()
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(25),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildHeader(theme),
                  const SizedBox(height: 25), _buildStatsGrid(theme),
                  const SizedBox(height: 35),
                  Text("My Articles", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  ..._myArticles.isNotEmpty ? _myArticles.take(10).map((a) => _articleRow(theme, a)) : [_emptyCard(theme, "No articles yet. Tap + to write your first.")],
                  const SizedBox(height: 35),
                  Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  _actionBtn(theme, LucideIcons.feather, "Write Article", "Draft a new news article", Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WriterStudioScreen()))),
                ]),
              ),
            ),
    );
  }

  Widget _buildShimmer() => SingleChildScrollView(
    padding: const EdgeInsets.all(25),
    child: Column(children: [
      ShimmerLoader.rectangular(height: 120, width: double.infinity),
      const SizedBox(height: 20), Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 90)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 90))]),
      const SizedBox(height: 25), ShimmerLoader.rectangular(height: 18, width: 100),
      const SizedBox(height: 15), ...List.generate(3, (_) => Padding(padding: const EdgeInsets.only(bottom: 10), child: ShimmerLoader.rectangular(height: 60))),
    ]),
  );

  Widget _buildError() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(LucideIcons.wifiOff, size: 48, color: Colors.grey.shade300),
    const SizedBox(height: 12), Text("Could not load", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20), ElevatedButton.icon(onPressed: _loadDashboard, icon: const Icon(LucideIcons.refreshCw, size: 16), label: const Text("Retry")),
  ]));

  Widget _buildHeader(ThemeData theme) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.amber.shade800, Colors.amber.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.amber.shade200.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)), child: const Icon(LucideIcons.feather, color: Colors.white, size: 28)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Writer's Studio", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          Text("$_publishedCount published â€¢ $_pendingCount drafts", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) => GridView.count(
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.2,
    children: [
      _statCard("Published", "$_publishedCount", LucideIcons.checkCircle, Colors.green),
      _statCard("Books Listed", "$_booksListed", LucideIcons.bookOpen, Theme.of(context).primaryColor),
      _statCard("Book Sales", "$_totalSales", LucideIcons.shoppingCart, Colors.amber),
      _statCard("Pending", "$_pendingCount", LucideIcons.clock, Colors.orange),
    ],
  );

  Widget _statCard(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: color, size: 20), const Spacer(),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
    ]),
  );

  Widget _articleRow(ThemeData theme, Map<String, dynamic> article) {
    final title = article['title'] as String? ?? 'Untitled';
    final status = (article['status'] ?? '').toString().isEmpty
        ? 'published'
        : article['status'].toString();
    final created = DateTime.tryParse(article['created_at']?.toString() ?? '');
    final when = created == null
        ? ''
        : '${created.day}/${created.month}/${created.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(when, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: status == 'published' ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: status == 'published' ? Colors.green : Colors.orange)),
        ),
      ]),
    );
  }

  Widget _actionBtn(ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        ])),
        Icon(LucideIcons.chevronRight, size: 18, color: Colors.grey.shade300),
      ]),
    ),
  );

  Widget _emptyCard(ThemeData theme, String msg) => Container(
    width: double.infinity, padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: Center(child: Text(msg, style: TextStyle(color: Colors.grey.shade400))),
  );

}
