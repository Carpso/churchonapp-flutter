import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  final List<Map<String, dynamic>> _members = [
    {"name": "John Mwansa", "role": "Pastor", "status": "Active", "avatar": "https://i.pravatar.cc/150?u=1"},
    {"name": "Sarah Phiri", "role": "Worship Leader", "status": "Active", "avatar": "https://i.pravatar.cc/150?u=2"},
    {"name": "Mary Zulu", "role": "Member", "status": "Baptized", "avatar": "https://i.pravatar.cc/150?u=3"},
    {"name": "David Lungu", "role": "Elder", "status": "Active", "avatar": "https://i.pravatar.cc/150?u=4"},
    {"name": "Hope Banda", "role": "Visitor", "status": "Pending", "avatar": "https://i.pravatar.cc/150?u=5"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Member Directory"),
        actions: [
          IconButton(icon: const Icon(LucideIcons.search), onPressed: () {}),
          IconButton(icon: const Icon(LucideIcons.userPlus), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _members.length,
              itemBuilder: (context, index) => _buildMemberCard(_members[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _buildChip("All People", true),
          _buildChip("Pastors", false),
          _buildChip("Members", false),
          _buildChip("Baptized", false),
          _buildChip("Visitors", false),
        ],
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundImage: NetworkImage(member['avatar']),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(member['role'], style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: member['status'] == 'Active' || member['status'] == 'Baptized' 
                ? Colors.green.withOpacity(0.1) 
                : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              member['status'].toUpperCase(),
              style: TextStyle(
                color: member['status'] == 'Active' || member['status'] == 'Baptized' ? Colors.green : Colors.orange,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(LucideIcons.moreVertical, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}
