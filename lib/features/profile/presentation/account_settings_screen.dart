import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/r2_service.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/error_retry_widget.dart';
import '../../../core/i18n/app_languages.dart';
import '../../../core/i18n/l10n.dart';
import '../../auth/presentation/select_church_screen.dart'
    show SelectTenantScreen;

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  bool _isUploading = false;
  bool _isExporting = false;
  bool _isDeleting = false;

  Future<void> _exportMyData() async {
    setState(() => _isExporting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('export-user-data');
      final data = res.data;
      final jsonStr = data is String ? data : const JsonEncoder.withIndent('  ').convert(data);
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(jsonStr)),
        mimeType: 'application/json',
        name: 'churchonapp_my_data.json',
      );
      await SharePlus.instance.share(ShareParams(files: [file], text: 'My Church On App data export'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _deleteAccount() async {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deletion is unavailable for this sign-in method.')));
      return;
    }
    final typed = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        String value = '';
        return AlertDialog(
          title: const Text('Delete Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This permanently deletes your account and anonymises your posts, messages and comments. This cannot be undone.'),
              const SizedBox(height: 12),
              Text('Type $email to confirm:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              TextField(onChanged: (v) => value = v, decoration: const InputDecoration(hintText: 'Email')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('CANCEL')),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, value.trim().toLowerCase() == email.toLowerCase() ? email : null),
              child: const Text('DELETE', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    if (typed == null) return;
    setState(() => _isDeleting = true);
    try {
      await Supabase.instance.client.functions.invoke('delete-account', body: {'confirm_email': typed});
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

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
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: avatar.isNotEmpty
                        ? ClipOval(child: AppImage(avatar, width: 112, height: 112, fit: BoxFit.cover))
                        : null,
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
            const SizedBox(height: 20),
            _buildSwitchTenantTile(context),
            const SizedBox(height: 15),
            _buildActionTile(
              icon: LucideIcons.download,
              title: 'Download My Data',
              subtitle: 'Export everything you own as JSON',
              busy: _isExporting,
              onTap: _isExporting ? null : _exportMyData,
            ),
            const SizedBox(height: 15),
            _buildActionTile(
              icon: LucideIcons.trash2,
              title: 'Delete Account',
              subtitle: 'Permanently remove your account',
              busy: _isDeleting,
              danger: true,
              onTap: _isDeleting ? null : _deleteAccount,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => _closeOrSwitch(context),
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

  /// Safe close: if this screen is a pushed route, pop it. When it is embedded
  /// as a shell tab (e.g. the bookshop workspace has no route to pop), opening
  /// the tenant chooser keeps the user in the app instead of popping the root
  /// route — which previously left a blank white screen.
  void _closeOrSwitch(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelectTenantScreen()),
    );
  }

  Widget _buildSwitchTenantTile(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SelectTenantScreen()),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.arrowLeftRight),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('Switch Church / Bookshop'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    'Choose another church or bookshop to enter',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 18),
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

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool busy = false,
    bool danger = false,
  }) {
    final color = danger ? Colors.red : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
            if (busy)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(LucideIcons.chevronRight, size: 18),
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

