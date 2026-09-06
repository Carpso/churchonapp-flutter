import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/providers/profile_provider.dart';
import '../data/network_service.dart';

class InterchurchNetworkScreen extends ConsumerStatefulWidget {
  const InterchurchNetworkScreen({super.key});

  @override
  ConsumerState<InterchurchNetworkScreen> createState() => _InterchurchNetworkScreenState();
}

class _InterchurchNetworkScreenState extends ConsumerState<InterchurchNetworkScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final churchesAsync = ref.watch(connectedChurchesProvider(_searchQuery.isNotEmpty ? _searchQuery : null));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Church Network"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (v) {
                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted) setState(() => _searchQuery = v);
                });
              },
              decoration: InputDecoration(
                hintText: 'Search churches by name or location...',
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.xCircle, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ),
          Expanded(
            child: churchesAsync.when(
              data: (churches) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(connectedChurchesProvider);
                },
                child: churches.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                          Center(
                            child: Column(
                              children: [
                                Icon(LucideIcons.church, size: 60, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                const Text("No churches found in your network", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                const Text("Try a different search term", style: TextStyle(color: Colors.grey, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: churches.length,
                        itemBuilder: (context, index) => _buildChurchCard(context, churches[index]),
                      ),
              ),
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
              error: (err, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.wifiOff, size: 50, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text("Error: $err", style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text("Retry"),
                      onPressed: () => ref.invalidate(connectedChurchesProvider),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChurchCard(BuildContext context, ConnectedChurch church) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: church.logoUrl != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(16), child: AppImage(church.logoUrl!, fit: BoxFit.cover))
                    : const Icon(LucideIcons.church, color: Colors.amber, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(church.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (church.location != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(LucideIcons.mapPin, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(church.location!, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(LucideIcons.users, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text("${church.memberCount} members", style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600)),
              if (church.nextProgramName != null) ...[
                const SizedBox(width: 12),
                Icon(LucideIcons.calendar, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  church.nextProgramName!,
                  style: TextStyle(color: Colors.amber.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: () => _showChurchOptions(context, church),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.plusCircle, size: 14, color: Colors.amber.shade800),
                      const SizedBox(width: 6),
                      Text("Connect", style: TextStyle(color: Colors.amber.shade800, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmConnect(BuildContext context, ConnectedChurch church) async {
    final profile = ref.read(profileProvider).value;
    if (profile == null || profile.tenantId == null || profile.tenantId!.isEmpty) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("No Church Selected"),
          content: const Text(
            "You need to belong to a church before you can connect to other churches on the network. Please join your church first from the home screen.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Connect to ${church.name}?"),
        content: const Text(
          "This will link your church to this one on the network so you can follow each other's updates, events and prayer requests.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Connect"),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(networkServiceProvider).connectToChurch(church.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connected to ${church.name}"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connection failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showChurchOptions(BuildContext context, ConnectedChurch church) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.church, color: Colors.amber, size: 28),
                const SizedBox(width: 12),
                Expanded(child: Text(church.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              ],
            ),
            if (church.location != null) ...[
              const SizedBox(height: 8),
              Row(children: [Icon(LucideIcons.mapPin, size: 14, color: Colors.grey.shade400), const SizedBox(width: 6), Text(church.location!, style: const TextStyle(color: Colors.grey, fontSize: 13))]),
            ],
            const SizedBox(height: 8),
            Row(children: [Icon(LucideIcons.users, size: 14, color: Colors.grey.shade400), const SizedBox(width: 6), Text("${church.memberCount} members", style: TextStyle(color: Colors.grey.shade600, fontSize: 13))]),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmConnect(context, church);
                },
                icon: const Icon(LucideIcons.plusCircle, size: 18),
                label: const Text("Connect to this Church"),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/church-social/${church.tenantId ?? church.id}');
                },
                icon: const Icon(LucideIcons.eye, size: 18),
                label: const Text("View Public Page"),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
