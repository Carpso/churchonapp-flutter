import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Theme via context
import '../data/marketplace_service.dart';
import '../../../core/widgets/pdf_viewer_screen.dart';

class LibraryItem {
  final String id;
  final String title;
  final String image;
  final String downloadUrl;

  LibraryItem({required this.id, required this.title, required this.image, required this.downloadUrl});
}

class MyLibraryScreen extends ConsumerWidget {
  const MyLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // In a real app, we'd fetch from orders table
    final mockItems = [
      LibraryItem(id: '1', title: "Kingdom Stewardship", image: "https://images.unsplash.com/photo-1544947950-fa07a98d237f?w=400", downloadUrl: ""),
      LibraryItem(id: '2', title: "The Faith Manual", image: "https://images.unsplash.com/photo-1589829085413-56de8ae18c73?w=400", downloadUrl: ""),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("My Library", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: mockItems.isEmpty 
        ? _buildEmptyState()
        : GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 0.7,
            ),
            itemCount: mockItems.length,
            itemBuilder: (context, index) => _buildLibraryCard(context, mockItems[index]),
          ),
    );
  }

  Widget _buildLibraryCard(BuildContext context, LibraryItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
              child: Image.network(item.image, fit: BoxFit.cover, width: double.infinity),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: Text("READ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Theme.of(context).colorScheme.secondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.bookOpen, size: 50, color: Colors.grey),
          const SizedBox(height: 20),
          const Text("Library is empty", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          Text("Books you purchase will appear here", style: TextStyle(color: Colors.grey.withOpacity(0.6))),
        ],
      ),
    );
  }
}

