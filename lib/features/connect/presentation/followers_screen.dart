import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/connect/data/follow_service.dart';

/// Followers / Following list for a user.
///
/// Follows were only reachable from a deep-link handler with no way to see WHO
/// follows you — this makes the counts real, browsable lists with inline
/// follow/unfollow, consistent with the Connect feed.
class FollowersScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool showFollowing;
  const FollowersScreen({
    super.key,
    required this.userId,
    this.showFollowing = false,
  });

  @override
  ConsumerState<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends ConsumerState<FollowersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _following = [];
  bool _loading = true;
  final Set<String> _busy = {};
  final Set<String> _iFollow = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: 2, vsync: this, initialIndex: widget.showFollowing ? 1 : 0);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final svc = ref.read(followServiceProvider);
    try {
      final results = await Future.wait([
        svc.fetchFollowers(widget.userId),
        svc.fetchFollowing(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _followers = results[0];
        _following = results[1];
        _loading = false;
      });
      // Which of these people do I already follow?
      for (final p in [..._followers, ..._following]) {
        final id = p['id']?.toString();
        if (id == null) continue;
        svc.isFollowing(id).then((v) {
          if (mounted) setState(() => v ? _iFollow.add(id) : _iFollow.remove(id));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String userId) async {
    setState(() => _busy.add(userId));
    try {
      final nowFollowing =
          await ref.read(followServiceProvider).toggleFollow(userId);
      if (mounted) {
        setState(() {
          if (nowFollowing) {
            _iFollow.add(userId);
          } else {
            _iFollow.remove(userId);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update follow: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Followers'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'FOLLOWERS (${_followers.length})'),
            Tab(text: 'FOLLOWING (${_following.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _list(_followers, 'No followers yet'),
                _list(_following, 'Not following anyone yet'),
              ],
            ),
    );
  }

  Widget _list(List<Map<String, dynamic>> people, String emptyText) {
    if (people.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.users, size: 44, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(emptyText,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: people.length,
      itemBuilder: (context, i) {
        final p = people[i];
        final id = p['id']?.toString() ?? '';
        final name = (p['full_name'] ?? 'Member').toString();
        final role = (p['role'] ?? 'member').toString().toUpperCase();
        final avatar = (p['avatar_url'] ?? '').toString();
        final following = _iFollow.contains(id);
        final busy = _busy.contains(id);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey.shade200,
            backgroundImage:
                avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar.isEmpty
                ? const Icon(LucideIcons.user, size: 18)
                : null,
          ),
          title: Text(name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(role,
              style: const TextStyle(fontSize: 11, letterSpacing: 0.6)),
          onTap: () => context.push('/profile-by-id/$id'),
          trailing: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: () => _toggle(id),
                  style: TextButton.styleFrom(
                    backgroundColor: following
                        ? Colors.grey.shade200
                        : Theme.of(context).primaryColor,
                    foregroundColor: following ? Colors.black87 : Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text(
                    following ? 'FOLLOWING' : 'FOLLOW',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                ),
        );
      },
    );
  }
}
