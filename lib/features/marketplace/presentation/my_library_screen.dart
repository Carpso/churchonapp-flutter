import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
// Theme via context
import '../../../core/widgets/pdf_viewer_screen.dart';

class LibraryItem {
  final String id;
  final String title;
  final String image;
  final String downloadUrl;

  LibraryItem({
    required this.id,
    required this.title,
    required this.image,
    required this.downloadUrl,
  });
}

// 1. Provider to fetch library items from Supabase
final myLibraryProvider = FutureProvider<List<LibraryItem>>((ref) async {
  final client = ref.watch(supabaseServiceProvider).client;
  final user = client.auth.currentUser;

  if (user == null) {
    return [];
  }

  // This assumes you have an 'orders' or 'user_purchases' table
  // that links a user to a purchased item (e.g., a book from 'marketplace_items').
  // The query needs to be adapted to your actual schema.
  final response = await client
      .from('user_purchases')
      .select('*, marketplace_items(*)') // Join with the item table
      .eq('user_id', user.id);

  return response.map((purchase) {
    final item = purchase['marketplace_items'];
    return LibraryItem(
      id: item['id'].toString(),
      title: item['name'] ?? 'Untitled',
      image: item['image'] ?? '',
      // Assuming a 'download_url' field on the purchased item
      downloadUrl: item['download_url'] ?? '',
    );
  }).toList();
});

class MyLibraryScreen extends ConsumerWidget {
  const MyLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryItemsAsync = ref.watch(myLibraryProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          "My Library",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: libraryItemsAsync.when(
        data: (items) =>
            items.isEmpty ? _buildEmptyState() : _buildGridView(items),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: ${err.toString()}')),
      ),
    );
  }

  Widget _buildLibraryCard(BuildContext context, LibraryItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(25),
              ),
              child: AppImage(
                item.image,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PDFViewerScreen(
                          url: item.downloadUrl.isNotEmpty
                              ? item.downloadUrl
                              : "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", // Mock PDF
                          title: item.title,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    minimumSize: const Size(double.infinity, 35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    "READ",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(List<LibraryItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
        childAspectRatio: 0.7,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _buildLibraryCard(context, items[index]);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.bookOpen, size: 50, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            "Library is empty",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          Text(
            "Books you purchase will appear here",
            style: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
