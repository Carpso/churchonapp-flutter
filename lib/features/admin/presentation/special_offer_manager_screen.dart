import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_io/io.dart' show File;

import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/features/home/data/special_offer_service.dart';

/// All offers (active + inactive) for the owner/team manager.
final allSpecialOffersProvider =
    FutureProvider.autoDispose<List<SpecialOffer>>((ref) async {
  final client = Supabase.instance.client;
  try {
    final res = await client
        .from('special_offers')
        .select()
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) =>
            SpecialOffer.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    debugPrint('Error loading all special offers: $e');
    return const [];
  }
});

/// Owner/team CRUD for the home-screen promotional carousel.
class SpecialOfferManagerScreen extends ConsumerWidget {
  const SpecialOfferManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(canManageSpecialOffersProvider);
    return canManage.when(
      data: (allowed) {
        if (!allowed) {
          return Scaffold(
            appBar: AppBar(title: const Text('Special Offers')),
            body: const Center(
              child: Text('Superadmin / COA Employee access required'),
            ),
          );
        }
        return _SpecialOffersList();
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => Scaffold(
        appBar: AppBar(title: const Text('Special Offers')),
        body: Center(
          child: TextButton(
            onPressed: () => ref.invalidate(canManageSpecialOffersProvider),
            child: const Text('Retry'),
          ),
        ),
      ),
    );
  }
}

class _SpecialOffersList extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SpecialOffersList> createState() => _SpecialOffersListState();
}

class _SpecialOffersListState extends ConsumerState<_SpecialOffersList> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offersAsync = ref.watch(allSpecialOffersProvider);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Special Offers'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(LucideIcons.plus),
        label: const Text('New Offer'),
      ),
      body: offersAsync.when(
        data: (offers) {
          if (offers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.tag,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  const Text('No offers yet. Create your first one!'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: offers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final offer = offers[i];
              return _buildOfferTile(theme, offer);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(allSpecialOffersProvider),
            child: const Text('Retry'),
          ),
        ),
      ),
    );
  }

  Widget _buildOfferTile(ThemeData theme, SpecialOffer offer) {
    final hasImage = offer.imageUrl != null && offer.imageUrl!.isNotEmpty;
    return GestureDetector(
      onTap: () => _openEditor(context, ref, offer),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: hasImage
                    ? AppImage(offer.imageUrl!, fit: BoxFit.cover)
                    : Container(
                        color: theme.primaryColor.withValues(alpha: 0.15),
                        child: Icon(
                          LucideIcons.tag,
                          color: theme.primaryColor,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (offer.promoted) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'PROMOTED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: offer.isActive
                              ? Colors.green.withValues(alpha: 0.15)
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.1,
                                ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          offer.isActive ? 'ACTIVE' : 'HIDDEN',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: offer.isActive
                                ? Colors.green.shade800
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    offer.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (offer.subtitle != null &&
                      offer.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      offer.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: () => _deleteOffer(offer),
              icon: Icon(
                LucideIcons.trash2,
                size: 18,
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteOffer(SpecialOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete offer?'),
        content: Text('"${offer.title}" will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client
          .from('special_offers')
          .delete()
          .eq('id', offer.id);
      if (mounted) {
        ref.invalidate(allSpecialOffersProvider);
        ref.invalidate(activeSpecialOffersProvider);
        showAppSnackBar(
          context,
          'Offer deleted.',
          status: AppStatus.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }

  void _openEditor(
    BuildContext context,
    WidgetRef ref,
    SpecialOffer? offer,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) =>
          _OfferEditorSheet(offer: offer, onSaved: () {
        ref.invalidate(allSpecialOffersProvider);
        ref.invalidate(activeSpecialOffersProvider);
      }),
    );
  }
}

class _OfferEditorSheet extends ConsumerStatefulWidget {
  final SpecialOffer? offer;
  final VoidCallback onSaved;
  const _OfferEditorSheet({this.offer, required this.onSaved});

  @override
  ConsumerState<_OfferEditorSheet> createState() => _OfferEditorSheetState();
}

class _OfferEditorSheetState extends ConsumerState<_OfferEditorSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _badgeCtrl;
  late final TextEditingController _targetCtrl;
  String _linkType = 'marketplace';
  bool _isActive = true;
  bool _promoted = false;
  String? _imageUrl;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final offer = widget.offer;
    _titleCtrl = TextEditingController(text: offer?.title ?? '');
    _subtitleCtrl = TextEditingController(text: offer?.subtitle ?? '');
    _badgeCtrl = TextEditingController(
      text: offer?.badge ?? 'SPECIAL OFFER',
    );
    _targetCtrl = TextEditingController(text: offer?.linkTarget ?? '');
    _linkType = offer?.linkType ?? 'marketplace';
    _isActive = offer?.isActive ?? true;
    _promoted = offer?.promoted ?? false;
    _imageUrl = offer?.imageUrl;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _badgeCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1400,
      maxHeight: 700,
    );
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final file = File(picked.path);
      final url = await ref
          .read(r2ServiceProvider)
          .uploadFile(
            file,
            'special-offers/offer_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
      if (url == null) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          'Image upload failed. Please try again.',
          status: AppStatus.error,
        );
        return;
      }
      setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      showAppSnackBar(
        context,
        'Title is required.',
        status: AppStatus.error,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final data = {
        'title': _titleCtrl.text.trim(),
        'subtitle': _subtitleCtrl.text.trim().isEmpty
            ? null
            : _subtitleCtrl.text.trim(),
        'badge': _badgeCtrl.text.trim().isEmpty
            ? null
            : _badgeCtrl.text.trim(),
        'image_url': _imageUrl,
        'link_type': _linkType,
        'link_target': (_linkType == 'none' || _targetCtrl.text.trim().isEmpty)
            ? null
            : _targetCtrl.text.trim(),
        'is_active': _isActive,
        'promoted': _promoted,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (widget.offer == null) {
        data['created_by'] = client.auth.currentUser?.id;
        await client.from('special_offers').insert(data);
      } else {
        await client
            .from('special_offers')
            .update(data)
            .eq('id', widget.offer!.id);
      }
      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        showAppSnackBar(
          context,
          widget.offer == null ? 'Offer created!' : 'Offer updated!',
          status: AppStatus.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = _imageUrl != null && _imageUrl!.isNotEmpty;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 30,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.offer == null ? 'New Offer' : 'Edit Offer',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Shown in the home screen promo carousel. Promoted offers appear first.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _uploading ? null : _pickImage,
              child: Container(
                height: 110,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _uploading
                    ? const Center(child: CircularProgressIndicator())
                    : hasImage
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              AppImage(_imageUrl!, fit: BoxFit.cover),
                              Container(
                                alignment: Alignment.center,
                                color: Colors.black.withValues(alpha: 0.35),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Change image',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: theme.primaryColor,
                                  size: 28,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Add banner image (optional)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title *',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subtitleCtrl,
              decoration: const InputDecoration(
                labelText: 'Subtitle',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _badgeCtrl,
              decoration: const InputDecoration(
                labelText: 'Badge (e.g. SPECIAL OFFER, NEW)',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _linkType,
              decoration: const InputDecoration(
                labelText: 'On tap goes to',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'marketplace',
                  child: Text('Marketplace (bookshop)'),
                ),
                DropdownMenuItem(
                  value: 'web',
                  child: Text('External website link'),
                ),
                DropdownMenuItem(
                  value: 'none',
                  child: Text('Nothing'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _linkType = v);
              },
            ),
            if (_linkType != 'none') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _targetCtrl,
                decoration: InputDecoration(
                  labelText: _linkType == 'web'
                      ? 'URL (https://...)'
                      : 'Marketplace category (e.g. bookshop)',
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Active',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Visible in the home carousel'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Promoted',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Shown first, highlighted on the home screen'),
              value: _promoted,
              onChanged: (v) => setState(() => _promoted = v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.offer == null ? 'CREATE OFFER' : 'SAVE CHANGES',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
