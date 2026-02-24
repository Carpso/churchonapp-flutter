import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/admin_service.dart';
import '../../../core/providers/profile_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MemberManagementScreen extends ConsumerStatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  ConsumerState<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends ConsumerState<MemberManagementScreen> {
  String _filter = "All People";

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersStreamProvider);

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
            child: membersAsync.when(
              data: (members) {
                final filtered = _filter == "All People" 
                  ? members 
                  : members.where((m) => m.role?.toLowerCase() == _filter.toLowerCase().replaceAll('s', '')).toList();
                
                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _buildMemberCard(filtered[index]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text("Error: $err")),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final categories = ["All People", "Pastors", "Members", "Drivers", "Riders", "Elders", "Visitors"];
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: categories.length,
        itemBuilder: (context, index) => _buildChip(categories[index], _filter == categories[index]),
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _filter = label),
      child: Container(
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
      ),
    );
  }

  Widget _buildMemberCard(UserProfile member) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundImage: NetworkImage("https://i.pravatar.cc/150?u=${member.id.hashCode}"),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(member.role?.toUpperCase() ?? 'MEMBER', style: TextStyle(color: Colors.grey.shade600, fontSize: 10, letterSpacing: 1.1)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              "ACTIVE",
              style: TextStyle(
                color: Colors.green,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.moreVertical, size: 18, color: Colors.grey),
            onSelected: (val) {
              ref.read(adminServiceProvider).updateUserRole(member.id, val);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'member', child: Text("Set as Member")),
              const PopupMenuItem(value: 'driver', child: Text("Set as Kingdom Driver")),
              const PopupMenuItem(value: 'rider', child: Text("Set as Kingdom Rider")),
              const PopupMenuItem(value: 'pastor', child: Text("Set as Pastor")),
              const PopupMenuItem(value: 'employee', child: Text("Set as Employee")),
              const PopupMenuItem(value: 'admin', child: Text("Promote to Admin")),
            ],
          ),
        ],
      ),
    );
  }
}
