import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:church_on_app/features/marketplace/data/marketplace_service.dart';
import 'package:church_on_app/features/marketplace/presentation/product_details_screen.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';

class HomeSparkleGrid extends ConsumerWidget {
  const HomeSparkleGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    final productsAsync = ref.watch(productsProvider({'category': 'all', 'tenantId': tenant?.id ?? ''}));

    return productsAsync.when(
      data: (products) {
        final displayProducts = products.take(4).toList();
        if (displayProducts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text("No items available")),
          );
        }
        return MasonryGridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          itemCount: displayProducts.length,
          itemBuilder: (context, index) {
            final prod = displayProducts[index];
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProductDetailsScreen(product: prod))),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Theme.of(context).shadowColor.withValues(alpha: 0.02), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: AppImage(
                        prod.image != null && prod.image!.isNotEmpty ? prod.image! : "",
                        width: double.infinity,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(prod.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                      "K${prod.price.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: MasonryGridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          itemCount: 4,
          itemBuilder: (context, index) => Container(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                const ShimmerLoader.rectangular(height: 120),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerLoader.rectangular(width: 100, height: 14),
                      const SizedBox(height: 8),
                      ShimmerLoader.rectangular(width: 60, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      error: (e, s) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text("Error loading picks")),
      ),
    );
  }
}
