import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import '../data/ad_service.dart';

class PlatformAdScreen extends ConsumerStatefulWidget {
  const PlatformAdScreen({super.key});

  @override
  ConsumerState<PlatformAdScreen> createState() => _PlatformAdScreenState();
}

class _PlatformAdScreenState extends ConsumerState<PlatformAdScreen> {
  @override
  Widget build(BuildContext context) {
    final adsAsync = ref.watch(allAdsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Ads'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => _showAdDialog(null),
          ),
        ],
      ),
      body: adsAsync.when(
        data: (ads) => ads.isEmpty
            ? const Center(child: Text('No ads yet. Tap + to create one.'))
            : ListView.builder(
                itemCount: ads.length,
                itemBuilder: (context, index) {
                  final ad = ads[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: ad.imageUrl != null
                              ? AppImage(ad.imageUrl!, width: 56, height: 56, fit: BoxFit.cover, borderRadius: BorderRadius.circular(8))
                              : Icon(ad.isPlatformWide ? LucideIcons.globe : LucideIcons.building2, size: 32, color: Colors.amber),
                          title: Text(ad.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${ad.adType} — ${ad.placement}'),
                              Row(
                                children: [
                                  if (ad.isPlatformWide)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('PLATFORM', style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)),
                                    ),
                                  if (!ad.isPlatformWide) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('TENANT', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(ad.isActive ? LucideIcons.checkCircle : LucideIcons.xCircle,
                                  color: ad.isActive ? Colors.green : Colors.red, size: 20),
                              IconButton(
                                icon: const Icon(LucideIcons.pencil, size: 18),
                                onPressed: () => _showAdDialog(ad),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        loading: () => const Center(child: ListSkeleton()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showAdDialog(TenantAd? existing) {
    final titleC = TextEditingController(text: existing?.title);
    final descC = TextEditingController(text: existing?.description ?? '');
    final urlC = TextEditingController(text: existing?.targetUrl ?? '');
    final imgC = TextEditingController(text: existing?.imageUrl ?? '');
    String type = existing?.adType ?? 'banner';
    String placement = existing?.placement ?? 'home';
    bool isPlatformWide = existing?.isPlatformWide ?? true;
    int priority = existing?.priority ?? 0;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'New Platform Ad' : 'Edit Ad'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleC, decoration: const InputDecoration(labelText: 'Title'), textCapitalization: TextCapitalization.sentences),
                TextField(controller: descC, decoration: const InputDecoration(labelText: 'Description'), textCapitalization: TextCapitalization.sentences, maxLines: 2),
                TextField(controller: imgC, decoration: const InputDecoration(labelText: 'Image URL'), keyboardType: TextInputType.url),
                TextField(controller: urlC, decoration: const InputDecoration(labelText: 'Target URL'), keyboardType: TextInputType.url),
                DropdownButtonFormField(
                  initialValue: type,
                  items: const ['banner', 'sponsored', 'promoted'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => type = v!),
                  decoration: const InputDecoration(labelText: 'Type'),
                ),
                DropdownButtonFormField(
                  initialValue: placement,
                  items: const ['home', 'events', 'marketplace', 'connect', 'all'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => placement = v!),
                  decoration: const InputDecoration(labelText: 'Placement'),
                ),
                TextField(
                  controller: TextEditingController(text: priority.toString()),
                  decoration: const InputDecoration(labelText: 'Priority (higher = shown first)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => priority = int.tryParse(v) ?? 0,
                ),
                SwitchListTile(
                  title: const Text('Platform-wide'),
                  subtitle: const Text('Show on all churches'),
                  value: isPlatformWide,
                  onChanged: (v) => setState(() => isPlatformWide = v),
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSubmitting ? null : () async {
                setState(() => isSubmitting = true);
                try {
                  final supabase = ref.read(supabaseServiceProvider);
                  final userId = supabase.client.auth.currentUser?.id ?? '';
                  final data = {
                    'title': titleC.text,
                    'description': descC.text.isNotEmpty ? descC.text : null,
                    'image_url': imgC.text.isNotEmpty ? imgC.text : null,
                    'target_url': urlC.text.isNotEmpty ? urlC.text : null,
                    'ad_type': type,
                    'placement': placement,
                    'is_active': true,
                    'is_platform_wide': isPlatformWide,
                    'priority': priority,
                    'tenant_id': isPlatformWide ? null : null,
                    'created_by': userId,
                  };
                  if (existing == null) {
                    await ref.read(adServiceProvider).createAd(data);
                  } else {
                    await ref.read(adServiceProvider).updateAd(existing.id, data);
                  }
                  ref.invalidate(allAdsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (ctx.mounted) PremiumToast.showSuccess(ctx, existing == null ? 'Ad created!' : 'Ad updated!');
                } catch (e) {
                  if (!ctx.mounted) return;
                  PremiumToast.showError(ctx, 'Failed: $e');
                } finally {
                  setState(() => isSubmitting = false);
                }
              },
              child: isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(existing == null ? 'Create' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }
}
