import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/r2_service.dart';
import '../../../core/widgets/error_retry_widget.dart';
import '../../../core/i18n/app_languages.dart';
import '../../../core/i18n/l10n.dart';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  bool _isUploading = false;

  void _pickAndUploadImage() async {
    setState(() => _isUploading = true);

    try {
      final r2 = R2Service(Supabase.instance.client);
      final url = await r2.uploadAvatar(ImageSource.gallery);
      if (url == null) return;

      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile picture updated!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) => _buildScreen(context, profile),
      loading: () => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: ErrorRetryWidget(
          message: "Failed to load profile",
          onRetry: () => ref.invalidate(profileProvider),
        ),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, UserProfile? profile) {
    final userName = profile?.name ?? "Believer";
    final avatar = profile?.avatarUrl ?? '';
    final userId = profile?.id;
    final userCode = userId != null && userId.length >= 8 ? userId.substring(0, 8).toUpperCase() : "N/A";

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Account Settings"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(25, 25, 25, 140),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: CircleAvatar(
                    radius: 56,
                    backgroundImage: NetworkImage(avatar),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickAndUploadImage,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary, shape: BoxShape.circle),
                      child: _isUploading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(LucideIcons.camera, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            _buildSettingsInput("FULL NAME", userName, showEditIcon: true),
            const SizedBox(height: 15),
            _buildSettingsInput("ROLE", profile?.role.toUpperCase() ?? "MEMBER"),
            const SizedBox(height: 15),
            _buildSettingsInput("USER CODE", profile?.walletId ?? userCode),
            const SizedBox(height: 15),
            _buildLanguageSelector(context),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text("CLOSE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSelector(BuildContext context) {
    final language = ref.watch(appLanguageProvider);
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (sheetCtx) {
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.7,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        context.tr('Language'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    for (final lang in AppLanguage.values)
                      ListTile(
                        leading: Icon(
                          lang == language
                              ? LucideIcons.checkCircle
                              : LucideIcons.globe,
                          color: lang == language
                              ? Theme.of(context).colorScheme.secondary
                              : null,
                        ),
                        title: Text(lang.nativeName),
                        subtitle: Text(lang.name),
                        trailing: lang == language
                            ? Icon(
                                LucideIcons.check,
                                color: Theme.of(context).colorScheme.secondary,
                              )
                            : null,
                        onTap: () {
                          ref.read(appLanguageProvider.notifier).setLanguage(lang);
                          Navigator.pop(sheetCtx);
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.languages),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Language'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    language.nativeName,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronDown, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsInput(String label, String value, {bool showEditIcon = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value, 
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (showEditIcon) ...[
                const SizedBox(width: 10),
                const Icon(LucideIcons.edit2, size: 14, color: Colors.grey),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

