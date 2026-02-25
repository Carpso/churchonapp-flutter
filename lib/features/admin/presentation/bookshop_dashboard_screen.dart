import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../marketplace/presentation/post_product_screen.dart';

class BookshopDashboardScreen extends StatefulWidget {
  const BookshopDashboardScreen({super.key});

  @override
  State<BookshopDashboardScreen> createState() => _BookshopDashboardScreenState();
}

class _BookshopDashboardScreenState extends State<BookshopDashboardScreen> {
  final List<Map<String, dynamic>> _inventory = [
    {"title": "Dake Annotated Reference Bible", "stock": 45, "price": 450, "status": "In Stock"},
    {"title": "Purpose Driven Life Book", "stock": 12, "price": 200, "status": "Low Stock"},
    {"title": "Faith Over Fear Hoodie", "stock": 0, "price": 250, "status": "Out of Stock"},
    {"title": "Anointing Oil (Frankincense)", "stock": 120, "price": 65, "status": "In Stock"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Bookshop Management", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () {
              Navigator.push(
                context, 
                MaterialPageRoute(
                  builder: (context) => const PostProductScreen(initialCategory: "bookshop"),
                ),
              );
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Analytics Cards
            Row(
              children: [
                Expanded(child: _buildMetricCard("Total Sales (MTD)", "K 12,450", LucideIcons.trendingUp, Colors.green)),
                const SizedBox(width: 15),
                Expanded(child: _buildMetricCard("Low Stock Items", "2", LucideIcons.alertTriangle, Colors.orange)),
              ],
            ),
            const SizedBox(height: 30),
            const Text("Inventory Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ..._inventory.map((item) => _buildInventoryTile(item)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInventoryTile(Map<String, dynamic> item) {
    final statusColor = item['status'] == 'In Stock'
        ? Colors.green
        : item['status'] == 'Low Stock' ? Colors.orange : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.book, color: Theme.of(context).colorScheme.secondary),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text("Stock: ${item['stock']}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    const SizedBox(width: 15),
                    Text("Price: K${item['price']}", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(item['status'], style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}

