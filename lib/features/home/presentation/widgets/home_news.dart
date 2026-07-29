import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/features/home/data/news_service.dart';
import 'package:church_on_app/features/home/presentation/news_detail_screen.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeNews extends ConsumerWidget {
  const HomeNews({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicNewsAsync = ref.watch(publicNewsProvider);
    final kingdomNewsAsync = ref.watch(newsStreamProvider);

    return Column(
      children: [
        kingdomNewsAsync.when(
          data: (news) {
            if (news.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      const Text("Writers", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
                ...news.map((article) => _buildNewsCard(context, article)),
              ],
            );
          },
          loading: () => Column(
            children: List.generate(2, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Row(
                children: [
                  const ShimmerLoader.rectangular(width: 100, height: 100),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerLoader.rectangular(width: 60, height: 10),
                        const SizedBox(height: 8),
                        ShimmerLoader.rectangular(height: 14),
                        const SizedBox(height: 6),
                        ShimmerLoader.rectangular(width: 80, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
        publicNewsAsync.when(
          data: (news) {
            if (news.isEmpty) return const SizedBox.shrink();
            final kingdomTitles = kingdomNewsAsync.value?.map((a) => a.title.toLowerCase()).toSet() ?? {};
            final uniquePublicNews = news.where((a) => !kingdomTitles.contains(a.title.toLowerCase())).take(4).toList();
            if (uniquePublicNews.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 12),
                  child: Row(
                    children: [
                      Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      const Text("Global News", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
                ...uniquePublicNews.map((article) => _buildNewsCard(context, article)),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, s) => ErrorRetryWidget(
            message: "Failed to load news",
            onRetry: () => ref.invalidate(publicNewsProvider),
          ),
        ),
      ],
    );
  }

  Widget _buildNewsCard(BuildContext context, NewsArticle article) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: InkWell(
        onTap: () {
          if (article.isLocal) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => NewsDetailScreen(article: article)));
          } else {
            launchUrl(Uri.parse(article.link), mode: LaunchMode.inAppWebView);
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              child: AppImage(article.image, width: 100, height: 100, fit: BoxFit.cover),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.source.toUpperCase(),
                      style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 4),
                    Text(article.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(article.pubDate, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
