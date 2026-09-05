import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/features/admin/presentation/ministry_management_screen.dart';

final ministriesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final tenant = ref.watch(currentTenantProvider);
  if (tenant == null) return const Stream.empty();
  final client = Supabase.instance.client;
    return client
      .from('ministries')
      .stream(primaryKey: ['id'])
      .eq('tenant_id', tenant.id)
      .map((data) {
        final list = List<Map<String, dynamic>>.from(data);
        // Realtime streams must NOT use server-side .order() — sort client-side
        // to avoid refresh loops / disappearing content.
        list.sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
        return list;
      });
});

final userMinistryMembershipsProvider = FutureProvider.autoDispose((ref) async {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return <String>[];
  final res = await Supabase.instance.client
      .from('ministry_members')
      .select('ministry_id')
      .eq('profile_id', profile.id);
  return (res as List).map((r) => r['ministry_id'].toString()).toList();
});

final ministryMembersCountProvider = FutureProvider.family.autoDispose<int, String>((ref, ministryId) async {
  final res = await Supabase.instance.client
      .from('ministry_members')
      .select('id')
      .eq('ministry_id', ministryId);
  return (res as List).length;
});

class MinistriesScreen extends ConsumerStatefulWidget {
  /// When [embedded] is true the screen renders body-only (no Scaffold/AppBar)
  /// so it can live inside the Connect tab's Communities view.
  const MinistriesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<MinistriesScreen> createState() => _MinistriesScreenState();
}

class _MinistriesScreenState extends ConsumerState<MinistriesScreen> {
  final _client = Supabase.instance.client;
  late Future<Set<String>> _joinedFuture;

  @override
  void initState() {
    super.initState();
    _joinedFuture = _loadJoinedMinistries();
  }

  Future<Set<String>> _loadJoinedMinistries() async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return <String>{};
    final res = await _client
        .from('ministry_members')
        .select('ministry_id')
        .eq('profile_id', profile.id);
    return (res as List).map((r) => r['ministry_id'].toString()).toSet();
  }

  Future<void> _toggleJoin(Map<String, dynamic> ministry) async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    final ministryId = ministry['id'].toString();
    final joined = await _joinedFuture;
    if (!mounted) return;
    if (joined.contains(ministryId)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Leave ${ministry['name'] ?? 'ministry'}?'),
          content: const Text('Are you sure you want to leave this ministry? You will no longer receive ministry updates.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _client
          .from('ministry_members')
          .delete()
          .eq('ministry_id', ministryId)
          .eq('profile_id', profile.id);
      setState(() {
        _joinedFuture = _loadJoinedMinistries();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Left ${ministry['name'] ?? 'ministry'}'), backgroundColor: Colors.orange),
        );
      }
    } else {
      await _client.from('ministry_members').insert({
        'ministry_id': ministryId,
        'profile_id': profile.id,
        'tenant_id': profile.tenantId,
        'role': 'member',
        'joined_at': DateTime.now().toIso8601String(),
      });
      setState(() {
        _joinedFuture = _loadJoinedMinistries();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined ${ministry['name'] ?? 'ministry'}!'), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    if (tenant == null) {
      return Center(child: Text('Select a church first'));
    }

    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile != null && ['admin', 'pastor', 'bishop', 'superadmin', 'employee', 'coa_employee'].contains(profile.role);

    final body = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(ministriesStreamProvider);
        setState(() {
          _joinedFuture = _loadJoinedMinistries();
        });
      },
      child: ref.watch(ministriesStreamProvider).when(
        data: (ministries) {
          if (ministries.isEmpty) {
            return _buildEmptyState(context);
          }
          return FutureBuilder<Set<String>>(
            future: _joinedFuture,
            builder: (context, snapshot) {
              final joined = snapshot.data ?? <String>{};
              return ListView.builder(
                padding: EdgeInsets.fromLTRB(20, 10, 20, widget.embedded ? 40 : 100),
                itemCount: ministries.length,
                itemBuilder: (context, index) => _buildMinistryCard(ministries[index], joined, isAdmin),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Ministries'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        actions: isAdmin
            ? [
                IconButton(
                  icon: const Icon(LucideIcons.plus),
                  onPressed: () => _navigateToManagement(context),
                ),
              ]
            : null,
      ),
      body: body,
    );
  }

  void _navigateToManagement(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MinistryManagementScreen()),
    );
  }

  Widget _buildMinistryCard(Map<String, dynamic> ministry, Set<String> joined, bool isAdmin) {
    final ministryId = ministry['id'].toString();
    final isJoined = joined.contains(ministryId);
    final isActive = ministry['is_active'] != false;
    final leaderId = ministry['leader_id'] as String?;

    return FutureBuilder<Map<String, dynamic>?>(
      future: leaderId != null
          ? _client.from('profiles').select('full_name,avatar_url').eq('id', leaderId).maybeSingle()
          : Future.value(null),
      builder: (context, leaderSnapshot) {
        final leaderName = leaderSnapshot.data?['full_name']?.toString() ?? 'No leader';
        final leaderAvatar = leaderSnapshot.data?['avatar_url']?.toString();
        return FutureBuilder(
          future: _client.from('ministry_members').select('id').eq('ministry_id', ministryId),
          builder: (context, countSnapshot) {
            final count = (countSnapshot.data as List?)?.length ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (isActive ? Colors.amber : Colors.grey).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(LucideIcons.church, color: isActive ? Colors.amber : Colors.grey, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ministry['name']?.toString() ?? 'Unnamed Ministry',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (leaderAvatar != null && leaderAvatar.isNotEmpty)
                              AppImage(
                                leaderAvatar,
                                width: 16,
                                height: 16,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(8),
                              )
                            else
                              const Icon(LucideIcons.user, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Leader: $leaderName',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (ministry['description'] != null && (ministry['description'] as String).isNotEmpty)
                          Text(
                            ministry['description'] as String,
                            style: TextStyle(color: Colors.grey[600], fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(LucideIcons.clock, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              ministry['meeting_day'] != null
                                  ? '${ministry['meeting_day']} • ${ministry['meeting_time']}'
                                  : 'No meeting info',
                              style: TextStyle(color: Colors.grey[600], fontSize: 11),
                            ),
                            const SizedBox(width: 12),
                            Icon(LucideIcons.users, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text('$count members', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(LucideIcons.edit, size: 16),
                          onPressed: () => _navigateToManagement(context),
                        ),
                      isJoined
                          ? const Icon(LucideIcons.checkSquare, size: 20, color: Colors.amber)
                          : const Icon(LucideIcons.square, size: 20, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _toggleJoin(ministry),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isJoined ? Colors.grey[200] : Colors.amber.withValues(alpha: 0.15),
                      foregroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isJoined ? 'Joined' : 'Join',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile != null && ['admin', 'pastor', 'bishop', 'superadmin', 'employee', 'coa_employee'].contains(profile.role);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.church, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text('No ministries found', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          const SizedBox(height: 10),
          Text('Ministries help organize church activities and service opportunities',
              style: TextStyle(color: Colors.grey[400], fontSize: 12), textAlign: TextAlign.center),
          if (isAdmin) ...[
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _navigateToManagement(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text('Create Ministry'),
            ),
          ]
        ],
      ),
    );
  }
}