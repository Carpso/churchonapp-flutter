import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import '../data/news_service.dart';

class NewsListScreen extends ConsumerWidget {
  const NewsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicNewsAsync = ref.watch(publicNewsProvider);
    final kingdomNewsAsync = ref.watch(newsStreamProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.canPop() ? Navigator.pop(context) : context.go('/'),
        ),
        title: const Text("News", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(publicNewsProvider);
          ref.invalidate(newsStreamProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            kingdomNewsAsync.when(
              data: (news) => _buildSection(context, "Writers", news),
              loading: () => _buildNewsSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            publicNewsAsync.when(
              data: (news) => _buildSection(context, "Global Christian News", news),
              loading: () => _buildNewsSkeleton(),
              error: (e, s) => Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(LucideIcons.alertCircle, color: Colors.grey, size: 40),
                      const SizedBox(height: 10),
                      Text("Could not load news: $e", style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(publicNewsProvider),
                        child: const Text("RETRY"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: List.generate(2, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(
              height: 280,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            ),
          ),
        )),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<NewsArticle> articles) {
    if (articles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 15, top: 10),
          child: Row(
            children: [
              Container(width: 4, height: 18, decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        ...articles.map((article) => _buildNewsCard(context, article)),
      ],
    );
  }

  Widget _buildNewsCard(BuildContext context, NewsArticle article) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: InkWell(
        onTap: () {
          if (article.isLocal) {
            context.push('/news/${article.id}', extra: article);
          } else {
            launchUrl(Uri.parse(article.link), mode: LaunchMode.inAppWebView);
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppImage(
              article.image,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              errorWidget: (context, url) => Container(
                height: 180,
                color: Colors.grey[200],
                child: const Icon(LucideIcons.image, size: 48, color: Colors.grey),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(article.source.toUpperCase(), style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(LucideIcons.share2, size: 16),
                        color: Colors.grey,
                        onPressed: () => SharePlus.instance.share(ShareParams(
                          text: '${article.title}\n\n${article.link.isNotEmpty ? article.link : "Read more on Church On App!"}',
                        )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(article.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text(article.description, style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text(article.pubDate, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
