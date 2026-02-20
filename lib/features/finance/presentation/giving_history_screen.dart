import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class GivingHistoryScreen extends StatelessWidget {
  const GivingHistoryScreen({super.key});

  final List<Map<String, dynamic>> _history = const [
    {"type": "Tithe", "amount": "K 1,200.00", "date": "12 Feb 2024", "status": "Blessed"},
    {"type": "Offering", "amount": "K 200.00", "date": "05 Feb 2024", "status": "Blessed"},
    {"type": "Building Fund", "amount": "K 500.00", "date": "28 Jan 2024", "status": "Blessed"},
    {"type": "Mission", "amount": "K 100.00", "date": "15 Jan 2024", "status": "Blessed"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Stewardship History"),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(25),
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Column(
                children: [
                  const Text("ANNUAL CONTRIBUTIONS", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  const Text("K 12,450.00", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text("You are 80% towards your 2024 Kingdom Goal", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildHistoryItem(_history[index]),
                childCount: _history.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFFAEB), shape: BoxShape.circle),
            child: Icon(LucideIcons.heart, color: Colors.red.shade400, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(item['date'], style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(item['amount'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text(item['status'], style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
