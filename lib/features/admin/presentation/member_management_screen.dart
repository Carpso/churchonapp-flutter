import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/admin_service.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/widgets/app_image.dart';

class MemberManagementScreen extends ConsumerStatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  ConsumerState<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends ConsumerState<MemberManagementScreen> {
  String _filter = "All People";
  List<UserProfile> _members = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 50;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final service = ref.read(adminServiceProvider);
    final tenantId = ref.read(currentTenantProvider)?.id;
    final batch = await service.getMembers(tenantId: tenantId);
    if (mounted) {
      setState(() {
        _members = batch;
        _hasMore = batch.length >= _limit;
      });
    }
  }

  void _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      _offset += _limit;
      final service = ref.read(adminServiceProvider);
      final tenantId = ref.read(currentTenantProvider)?.id;
      final batch = await service.getMembers(tenantId: tenantId);
      if (mounted) {
        final more = batch.length > _offset ? batch.sublist(_offset) : <UserProfile>[];
        setState(() {
          _members = [..._members, ...more];
          _hasMore = more.length >= _limit;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      data: (currentProfile) => _buildScreen(context, currentProfile),
      loading: () => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, UserProfile? currentProfile) {
    var filtered = _filter == "All People"
        ? _members
        : _members.where((m) => m.role.toLowerCase() == _filter.toLowerCase().replaceAll('s', '')).toList();

    final isGlobalAdmin = currentProfile?.isSuperadmin == true || currentProfile?.role == 'coa_employee';
    final currentTenantId = currentProfile?.tenantId;
    if (!isGlobalAdmin && currentTenantId != null) {
      filtered = filtered.where((m) => m.tenantId == currentTenantId).toList();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Member Directory"),
        actions: [
          IconButton(icon: const Icon(LucideIcons.search), onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Search will filter members")),
            );
          }),
          IconButton(icon: const Icon(LucideIcons.userPlus), onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("Add Member"),
                content: const Text("Use the Admin Hub or invite a user through the Church On App platform to add a new member."),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
                ],
              ),
            );
          }),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _members = [];
                  _offset = 0;
                  _hasMore = true;
                });
                await _loadMembers();
              },
              child: _members.isEmpty && !_isLoadingMore
                  ? const Center(child: Text("No members found", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: filtered.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == filtered.length) {
                    return _isLoadingMore
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : GestureDetector(
                            onTap: _loadMore,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
                              ),
                              child: Center(
                                child: Text("Load More", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          );
                  }
                  return _buildMemberCard(filtered[index], currentProfile);
                },
              ),
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

  Widget _buildMemberCard(UserProfile member, UserProfile? currentProfile) {
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
            backgroundColor: Colors.grey[200],
              child: ClipOval(
              child: AppImage(member.avatarUrl ?? '', width: 50, height: 50, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(member.role.toUpperCase(), style: TextStyle(color: Colors.grey.shade600, fontSize: 10, letterSpacing: 1.1)),
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
            itemBuilder: (context) {
              final isGlobalAdmin = currentProfile?.isSuperadmin == true || currentProfile?.isEmployee == true;
              final tenant = ref.read(currentTenantProvider);
              final tenantId = tenant?.id;
              return [
                const PopupMenuItem(value: 'member', child: Text("Set as Member")),
                if (isGlobalAdmin) ...[
                  const PopupMenuItem(value: 'driver', child: Text("Set as Driver")),
                  const PopupMenuItem(value: 'rider', child: Text("Set as Rider")),
                  const PopupMenuItem(value: 'coa_employee', child: Text("Set as COA Employee")),
                ],
                const PopupMenuItem(value: 'pastor', child: Text("Set as Pastor")),
                const PopupMenuItem(value: 'admin', child: Text("Promote to Admin")),
                const PopupMenuDivider(),
                // Dynamic tenant roles
                if (tenantId != null) ...[
                  const PopupMenuItem(enabled: false, child: Text("── Church Roles ──", style: TextStyle(fontSize: 11, color: Colors.grey))),
                  const PopupMenuItem(value: 'deacon', child: Text("Set as Deacon")),
                  const PopupMenuItem(value: 'elder', child: Text("Set as Elder")),
                  const PopupMenuItem(value: 'treasurer', child: Text("Set as Treasurer")),
                  const PopupMenuItem(value: 'secretary', child: Text("Set as Secretary")),
                  const PopupMenuItem(value: 'usher', child: Text("Set as Usher")),
                  const PopupMenuItem(value: 'youth_leader', child: Text("Set as Youth Leader")),
                  const PopupMenuItem(value: 'worship_leader', child: Text("Set as Worship Leader")),
                  const PopupMenuItem(value: 'sunday_school_teacher', child: Text("Set as Sunday School Teacher")),
                  const PopupMenuItem(value: 'leader', child: Text("Set as Leader")),
                ],
              ];
            },
          ),
        ],
      ),
    );
  }
}

