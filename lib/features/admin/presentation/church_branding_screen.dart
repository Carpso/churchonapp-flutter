import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_io/io.dart' show File;

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/core/widgets/app_image.dart';

/// Lets a church's leaders set the hero banner + logo shown on the home
/// screen hero card. Images are uploaded to R2 and stored on the church row.
class ChurchBrandingScreen extends ConsumerStatefulWidget {
  const ChurchBrandingScreen({super.key});

  @override
  ConsumerState<ChurchBrandingScreen> createState() =>
      _ChurchBrandingScreenState();
}

class _ChurchBrandingScreenState extends ConsumerState<ChurchBrandingScreen> {
  bool _savingBanner = false;
  bool _savingLogo = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final tenant = ref.watch(currentTenantProvider);

    if (profile == null || !profile.isTenantAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Church Branding')),
        body: const Center(child: Text('Admin access required')),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Church Branding'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPreviewCard(theme, tenant),
            const SizedBox(height: 28),
            Text(
              'HERO BANNER',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            _buildImageTile(
              theme,
              title: 'Home Hero Background',
              subtitle:
                  'The banner shown behind the church card on the home screen (wide image, recommended 1600x600).',
              currentUrl: tenant?.bannerUrl,
              saving: _savingBanner,
              icon: LucideIcons.image,
              onPick: () => _pickAndSave('banner'),
              onRemove: tenant?.bannerUrl != null
                  ? () => _removeImage('banner')
                  : null,
            ),
            const SizedBox(height: 28),
            Text(
              'CHURCH LOGO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            _buildImageTile(
              theme,
              title: 'Church Logo',
              subtitle:
                  'The square logo used in the church card fallback, website and avatar.',
              currentUrl: tenant?.logoUrl,
              saving: _savingLogo,
              icon: LucideIcons.image,
              onPick: () => _pickAndSave('logo'),
              onRemove: tenant?.logoUrl != null
                  ? () => _removeImage('logo')
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ThemeData theme, Tenant? tenant) {
    final String? banner = tenant?.bannerUrl;
    final bgImage = (banner != null && banner.isNotEmpty)
        ? banner
        : (tenant?.logoUrl ?? "");
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PREVIEW',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppImage(
                bgImage,
                fit: BoxFit.cover,
                placeholder: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.primaryColor,
                        theme.colorScheme.surfaceContainerHighest,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      LucideIcons.church,
                      size: 56,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                errorWidget: (_, __) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.primaryColor,
                        theme.colorScheme.surfaceContainerHighest,
                      ],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.church,
                      size: 56,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                bottom: 14,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tenant?.name ?? 'My Church',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'GLORY TO GOD',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageTile(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required String? currentUrl,
    required bool saving,
    required IconData icon,
    required VoidCallback onPick,
    VoidCallback? onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: theme.primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          if (currentUrl != null && currentUrl.isNotEmpty) ...[
            Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: AppImage(currentUrl, fit: BoxFit.cover),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: saving ? null : onPick,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(saving ? 'Uploading...' : 'Change Image'),
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndSave(String kind) async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) {
      showAppSnackBar(
        context,
        'No church selected. Pick a church first.',
        status: AppStatus.error,
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
      maxHeight: 700,
    );
    if (picked == null) return;

    setState(() {
      if (kind == 'banner') {
        _savingBanner = true;
      } else {
        _savingLogo = true;
      }
    });
    try {
      final file = File(picked.path);
      final folder = kind == 'banner' ? 'church-banners' : 'church-logos';
      final fileName =
          '${tenant.id}-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await ref
          .read(r2ServiceProvider)
          .uploadFile(file, '$folder/$fileName');
      if (url == null) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          'Image upload failed. Please try again.',
          status: AppStatus.error,
        );
        return;
      }
      final column = kind == 'banner' ? 'banner_url' : 'logo_url';
      await Supabase.instance.client
          .from('churches')
          .update({column: url, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', tenant.id);
      await ref.read(currentTenantProvider.notifier).reload();
      if (mounted) {
        showAppSnackBar(
          context,
          kind == 'banner' ? 'Hero banner updated!' : 'Logo updated!',
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
      if (mounted) {
        setState(() {
          if (kind == 'banner') {
            _savingBanner = false;
          } else {
            _savingLogo = false;
          }
        });
      }
    }
  }

  Future<void> _removeImage(String kind) async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;
    final column = kind == 'banner' ? 'banner_url' : 'logo_url';
    try {
      await Supabase.instance.client
          .from('churches')
          .update({column: null, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', tenant.id);
      await ref.read(currentTenantProvider.notifier).reload();
      if (mounted) {
        showAppSnackBar(
          context,
          'Image removed.',
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
}
