import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/admin/data/ad_service.dart';
import 'package:church_on_app/features/admin/presentation/ad_payment_sheet.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/providers/profile_provider.dart';

class AdManagementScreen extends ConsumerStatefulWidget {
  const AdManagementScreen({super.key});

  @override
  ConsumerState<AdManagementScreen> createState() => _AdManagementScreenState();
}

class _AdManagementScreenState extends ConsumerState<AdManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) {
        if (profile == null || !(profile.isSuperadmin || profile.isEmployee)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Sponsored Content')),
            body: const Center(child: Text('Access denied. Superadmin or COA employee access required.')),
          );
        }
        return _buildContent(context);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Sponsored Content')),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final adsAsync = ref.watch(activeAdsProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sponsored Content'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAdDialog(context, ref, null),
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
                    child: ListTile(
                      leading: ad.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AppImage(ad.imageUrl!, width: 56, height: 56, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.ad_units, size: 40),
                      title: Text(ad.title),
                      subtitle: Text('${ad.adType} - ${ad.placement}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(ad.isActive ? Icons.check_circle : Icons.cancel, color: ad.isActive ? Colors.green : Colors.red),
                          IconButton(
                            icon: const Icon(Icons.monetization_on, size: 18, color: Colors.amber),
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => AdPaymentSheet(adId: ad.id),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _showAdDialog(context, ref, ad),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showAdDialog(BuildContext context, WidgetRef ref, TenantAd? existing) {
    final titleC = TextEditingController(text: existing?.title);
    final descC = TextEditingController(text: existing?.description ?? '');
    final urlC = TextEditingController(text: existing?.targetUrl ?? '');
    final imgC = TextEditingController(text: existing?.imageUrl ?? '');
    String type = existing?.adType ?? 'banner';
    String placement = existing?.placement ?? 'home';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'New Ad' : 'Edit Ad'),
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
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final tenantId =
                    ref.read(currentTenantProvider)?.id ??
                    ref.read(profileProvider).value?.tenantId;
                final data = {
                  'title': titleC.text,
                  'description': descC.text,
                  'image_url': imgC.text.isNotEmpty ? imgC.text : null,
                  'target_url': urlC.text.isNotEmpty ? urlC.text : null,
                  'ad_type': type,
                  'placement': placement,
                  'is_active': true,
                  if (tenantId != null && tenantId.isNotEmpty)
                    'tenant_id': tenantId,
                };
                try {
                  if (existing == null) {
                    await ref.read(adServiceProvider).createAd(data);
                  } else {
                    await ref.read(adServiceProvider).updateAd(existing.id, data);
                  }
                  ref.invalidate(activeAdsProvider(null));
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                }
              },
              child: Text(existing == null ? 'Create' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }
}
