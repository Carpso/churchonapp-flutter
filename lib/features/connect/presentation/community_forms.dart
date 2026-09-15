import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/community_service.dart';

/// Can the signed-in user manage (edit/delete) this community/group?
/// True for the creator, and for church leadership of the same tenant.
bool canManageCommunity(WidgetRef ref, Map<String, dynamic> row) {
  final profile = ref.read(profileProvider).value;
  if (profile == null) return false;
  final uid = row['createdBy']?.toString();
  if (uid != null && uid.isNotEmpty && uid == profile.id) return true;
  if (!profile.isLeadershipTeam) return false;
  final rowTenant = row['tenantId']?.toString();
  return rowTenant == null || rowTenant == profile.tenantId;
}

/// Create / edit a community.
Future<bool> showCommunityForm(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? existing,
}) async {
  final isEdit = existing != null;
  final nameCtrl =
      TextEditingController(text: existing?['name']?.toString() ?? '');
  final descCtrl =
      TextEditingController(text: existing?['description']?.toString() ?? '');
  var isPublic = existing?['isPublic'] as bool? ?? true;
  var busy = false;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Edit community' : 'New community',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Youth Fellowship',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isPublic,
                onChanged: (v) => setLocal(() => isPublic = v),
                title: const Text('Visible to my church only',
                    style: TextStyle(fontSize: 13)),
                subtitle: Text(
                    isPublic
                        ? 'Discoverable by everyone in the church'
                        : 'Private community',
                    style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          setLocal(() => busy = true);
                          try {
                            final service =
                                ref.read(communityServiceProvider);
                            if (isEdit) {
                              await service.updateCommunity(
                                existing['id'].toString(),
                                name: name,
                                description: descCtrl.text.trim(),
                                isPublic: isPublic,
                              );
                            } else {
                              await service.createCommunity(
                                name: name,
                                description: descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                                isPublic: isPublic,
                              );
                            }
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setLocal(() => busy = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Could not save: $e')));
                            }
                          }
                        },
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52)),
                  child: Text(isEdit ? 'SAVE CHANGES' : 'CREATE COMMUNITY'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  nameCtrl.dispose();
  descCtrl.dispose();
  if (saved == true) {
    ref.invalidate(communitiesStreamProvider);
    ref.invalidate(communityGroupsProvider);
  }
  return saved == true;
}

/// Create / edit a group. `communities` is used for the create case picker.
Future<bool> showGroupForm(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? existing,
  List<Map<String, dynamic>> communities = const [],
}) async {
  final isEdit = existing != null;
  final titleCtrl =
      TextEditingController(text: existing?['title']?.toString() ?? '');
  final subCtrl =
      TextEditingController(text: existing?['subtitle']?.toString() ?? '');
  var isAnnouncement = existing?['isAnnouncement'] as bool? ?? false;
  String? communityId = existing?['communityId']?.toString() ??
      (communities.isNotEmpty ? communities.first['id']?.toString() : null);
  var busy = false;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Edit group' : 'New group',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (!isEdit && communities.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: communityId,
                  decoration: const InputDecoration(
                      labelText: 'Community', border: OutlineInputBorder()),
                  items: communities
                      .map((c) => DropdownMenuItem(
                            value: c['id']?.toString(),
                            child: Text(c['name']?.toString() ?? 'Community'),
                          ))
                      .toList(),
                  onChanged: (v) => setLocal(() => communityId = v),
                ),
              if (!isEdit && communities.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                      'Create a community first, then add groups inside it.',
                      style: TextStyle(fontSize: 12)),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Group name',
                    hintText: 'e.g. Prayer Warriors',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isAnnouncement,
                onChanged: (v) => setLocal(() => isAnnouncement = v),
                title: const Text('Announcement group',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text('Only admins post; everyone reads',
                    style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) return;
                          setLocal(() => busy = true);
                          try {
                            final service =
                                ref.read(communityServiceProvider);
                            if (isEdit) {
                              await service.updateGroup(
                                existing['id'].toString(),
                                title: title,
                                subtitle: subCtrl.text.trim(),
                                isAnnouncement: isAnnouncement,
                              );
                            } else {
                              if (communityId == null) {
                                throw Exception('Pick a community');
                              }
                              await service.createGroup(
                                communityId: communityId!,
                                title: title,
                                subtitle: subCtrl.text.trim().isEmpty
                                    ? null
                                    : subCtrl.text.trim(),
                                isAnnouncement: isAnnouncement,
                              );
                            }
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setLocal(() => busy = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                      content: Text('Could not save: $e')));
                            }
                          }
                        },
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52)),
                  child: Text(isEdit ? 'SAVE CHANGES' : 'CREATE GROUP'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  titleCtrl.dispose();
  subCtrl.dispose();
  if (saved == true) {
    ref.invalidate(communitiesStreamProvider);
    ref.invalidate(communityGroupsProvider);
  }
  return saved == true;
}

/// Small menu used by the create buttons to choose what to add.
Future<String?> showCreateCommunityMenu(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Add to Communities',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(LucideIcons.users),
            title: const Text('New community'),
            subtitle: const Text('A container group for your church',
                style: TextStyle(fontSize: 11)),
            onTap: () => Navigator.pop(ctx, 'community'),
          ),
          ListTile(
            leading: const Icon(LucideIcons.messageSquare),
            title: const Text('New group'),
            subtitle: const Text('A chat group inside a community',
                style: TextStyle(fontSize: 11)),
            onTap: () => Navigator.pop(ctx, 'group'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
