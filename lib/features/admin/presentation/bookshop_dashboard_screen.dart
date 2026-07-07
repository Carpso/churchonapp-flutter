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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text("Bookshop Management", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          IconButton(
            icon: Icon(LucideIcons.plus, color: theme.colorScheme.onSurface),
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
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(seconds: 1));
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Expanded(child: _buildMetricCard("Total Sales (MTD)", "K 12,450", LucideIcons.trendingUp, Colors.green)),
                const SizedBox(width: 15),
                Expanded(child: _buildMetricCard("Low Stock Items", "2", LucideIcons.alertTriangle, Colors.orange)),
              ],
            ),
            const SizedBox(height: 30),
            Text("Inventory Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 15),
            ..._inventory.map((item) => _buildInventoryTile(item)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          Text(title, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInventoryTile(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final statusColor = item['status'] == 'In Stock'
        ? Colors.green
        : item['status'] == 'Low Stock' ? Colors.orange : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.book, color: Theme.of(context).colorScheme.secondary),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['title'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text("Stock: ${item['stock']}", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
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
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(item['status'], style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}
