import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_io/io.dart' show File;
import 'package:url_launcher/url_launcher.dart';

import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

/// Church website builder service
class ChurchWebsiteService {
  final SupabaseClient _client;

  ChurchWebsiteService(this._client);

  /// Get a church/bookshop website — matches by church_id OR tenant_id so
  /// bookshop tenants (no church row) work too.
  Future<Map<String, dynamic>?> getChurchWebsite(String tenantId) async {
    final result = await _client
        .from('church_websites')
        .select()
        .or('church_id.eq.$tenantId,tenant_id.eq.$tenantId')
        .maybeSingle();
    return result;
  }

  /// Resolve a website by pretty slug (public, anon-safe).
  Future<Map<String, dynamic>?> getWebsiteBySlug(String slug) async {
    final result = await _client
        .from('church_websites')
        .select()
        .eq('slug', slug.toLowerCase())
        .maybeSingle();
    return result;
  }

  /// Create/update church website
  Future<Map<String, dynamic>> saveWebsite({
    required String tenantId,
    required String title,
    String? subtitle,
    String? aboutText,
    String? logoUrl,
    String? bannerUrl,
    String? primaryColor,
    String? contactPhone,
    String? contactEmail,
    String? address,
    Map<String, dynamic>? serviceTimes,
    Map<String, dynamic>? socialLinks,
    List<Map<String, dynamic>>? sections,
    String? slug,
  }) async {
    final existing = await getChurchWebsite(tenantId);

    final data = <String, dynamic>{
      'church_id': _isUuid(tenantId) ? tenantId : null,
      'tenant_id': tenantId,
      'slug': (slug == null || slug.isEmpty) ? null : slug.toLowerCase(),
      'title': title,
      'subtitle': subtitle,
      'about_text': aboutText,
      'logo_url': logoUrl,
      'banner_url': bannerUrl,
      'primary_color': primaryColor ?? '#1B5E20',
      'contact_phone': contactPhone,
      'contact_email': contactEmail,
      'address': address,
      'service_times': serviceTimes ?? {},
      'social_links': socialLinks ?? {},
      'sections': sections ?? [],
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (existing != null) {
      final result = await _client
          .from('church_websites')
          .update(data)
          .eq('id', existing['id'])
          .select()
          .single();
      return result;
    } else {
      data['created_at'] = DateTime.now().toIso8601String();
      final result = await _client
          .from('church_websites')
          .insert(data)
          .select()
          .single();
      return result;
    }
  }

  /// Publish/unpublish website
  Future<void> togglePublish(String tenantId, bool publish) async {
    await _client
        .from('church_websites')
        .update({'is_published': publish, 'updated_at': DateTime.now().toIso8601String()})
        .or('church_id.eq.$tenantId,tenant_id.eq.$tenantId');
  }

  static bool _isUuid(String value) {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuid.hasMatch(value);
  }
}

final churchWebsiteServiceProvider = Provider<ChurchWebsiteService>((ref) {
  return ChurchWebsiteService(Supabase.instance.client);
});

/// Church website builder screen — one site per tenant (churches AND
/// bookshops), with logo/banner upload, custom sections and a pretty slug.
class ChurchWebsiteBuilderScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const ChurchWebsiteBuilderScreen({super.key, required this.tenantId});

  @override
  ConsumerState<ChurchWebsiteBuilderScreen> createState() =>
      _ChurchWebsiteBuilderScreenState();
}

class _ChurchWebsiteBuilderScreenState
    extends ConsumerState<ChurchWebsiteBuilderScreen> {
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _aboutController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _slugController = TextEditingController();
  String _primaryColor = '#1B5E20';
  String? _logoUrl;
  String? _bannerUrl;
  bool _isPublished = false;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingBanner = false;
  bool _uploadingLogo = false;
  int _viewCount = 0;

  final Map<String, String> _serviceTimes = {
    'Sunday': '',
    'Wednesday': '',
    'Friday': '',
  };

  final Map<String, String> _socialLinks = {
    'facebook': '',
    'instagram': '',
    'twitter': '',
    'youtube': '',
  };

  final List<Map<String, dynamic>> _sections = [];

  @override
  void initState() {
    super.initState();
    _loadWebsite();
  }

  Future<void> _loadWebsite() async {
    final service = ref.read(churchWebsiteServiceProvider);
    final website = await service.getChurchWebsite(widget.tenantId);
    final tenant = ref.read(currentTenantProvider);

    if (website != null) {
      _titleController.text = website['title'] ?? '';
      _subtitleController.text = website['subtitle'] ?? '';
      _aboutController.text = website['about_text'] ?? '';
      _phoneController.text = website['contact_phone'] ?? '';
      _emailController.text = website['contact_email'] ?? '';
      _addressController.text = website['address'] ?? '';
      _primaryColor = website['primary_color'] ?? '#1B5E20';
      _isPublished = website['is_published'] ?? false;
      _logoUrl = website['logo_url']?.toString();
      _bannerUrl = website['banner_url']?.toString();
      _viewCount = (website['view_count'] as num?)?.toInt() ?? 0;
      _slugController.text = website['slug']?.toString() ?? '';

      final times = website['service_times'] as Map<String, dynamic>? ?? {};
      times.forEach((key, value) {
        _serviceTimes[key] = value?.toString() ?? '';
      });

      final links = website['social_links'] as Map<String, dynamic>? ?? {};
      links.forEach((key, value) {
        _socialLinks[key] = value?.toString() ?? '';
      });

      final sections = website['sections'] as List? ?? [];
      _sections.addAll(
        sections.map(
          (s) => Map<String, dynamic>.from(s as Map),
        ),
      );
    }

    final tenantSlug = tenant?.slug;
    if (_slugController.text.isEmpty && tenantSlug != null) {
      _slugController.text = tenantSlug;
    }
    _slugController.text = _slugController.text.replaceAll(' ', '-').toLowerCase();
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(_slugController.text)) {
      _slugController.text = '';
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Website Builder')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Website Builder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.preview),
            tooltip: 'Preview',
            onPressed: _previewWebsite,
          ),
          Switch(
            value: _isPublished,
            onChanged: (value) => _togglePublish(value),
            activeThumbColor: Colors.green,
          ),
        ],
      ),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(
              'Preview & Links',
              [
                _buildImagePicker(
                  label: 'Hero Banner (wide, recommended 1600x600)',
                  url: _bannerUrl,
                  uploading: _uploadingBanner,
                  onPick: () => _pickImage('banner'),
                ),
                const SizedBox(height: 12),
                _buildImagePicker(
                  label: 'Logo (square)',
                  url: _logoUrl,
                  uploading: _uploadingLogo,
                  onPick: () => _pickImage('logo'),
                ),
                const SizedBox(height: 16),
                _buildLinkRow(
                  context,
                  icon: LucideIcons.globe,
                  label: 'Pretty link',
                  value: _prettyUrl,
                  copyValue: _prettyUrl,
                ),
                const SizedBox(height: 8),
                _buildLinkRow(
                  context,
                  icon: LucideIcons.link,
                  label: 'Fallback link',
                  value: 'https://churchonapp.com/church/${widget.tenantId}',
                  copyValue:
                      'https://churchonapp.com/church/${widget.tenantId}',
                ),
                if (_viewCount > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.eye,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_viewCount views',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            _buildSection(
              'Header',
              [
                _buildTextField('Title', _titleController),
                _buildTextField('Subtitle', _subtitleController),
                _buildTextField(
                  'Pretty link slug (e.g. rock-of-ages)',
                  _slugController,
                  hint: 'churchonapp.com/c/rock-of-ages',
                ),
              ],
            ),
            _buildSection(
              'About',
              [
                _buildTextField(
                  'About Your Church',
                  _aboutController,
                  maxLines: 5,
                ),
              ],
            ),
            _buildSection(
              'Contact',
              [
                _buildTextField('Phone', _phoneController, icon: Icons.phone),
                _buildTextField('Email', _emailController, icon: Icons.email),
                _buildTextField(
                  'Address',
                  _addressController,
                  icon: Icons.location_on,
                ),
              ],
            ),
            _buildSection(
              'Branding',
              [
                Row(
                  children: [
                    const Text('Primary Color'),
                    const Spacer(),
                    GestureDetector(
                      onTap: _showColorPicker,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _parseColor(_primaryColor),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _buildSection(
              'Service Times',
              _serviceTimes.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'e.g. 09:00 AM',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (value) =>
                              _serviceTimes[entry.key] = value,
                          controller: TextEditingController(text: entry.value),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            _buildSection(
              'Social Links',
              _socialLinks.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '${entry.key} URL',
                      prefixIcon: _getSocialIcon(entry.key),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => _socialLinks[entry.key] = value,
                    controller: TextEditingController(text: entry.value),
                  ),
                );
              }).toList(),
            ),
            _buildSection(
              'Custom Sections',
              [
                ..._sections.asMap().entries.map((entry) {
                  final index = entry.key;
                  final section = entry.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Section title (e.g. Ministries)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 13),
                                onChanged: (v) => section['title'] = v,
                                controller: TextEditingController(
                                  text: section['title']?.toString() ?? '',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                LucideIcons.trash2,
                                size: 18,
                                color: Colors.red.shade400,
                              ),
                              onPressed: () =>
                                  setState(() => _sections.removeAt(index)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Content',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 4,
                          style: const TextStyle(fontSize: 13),
                          onChanged: (v) => section['content'] = v,
                          controller: TextEditingController(
                            text: section['content']?.toString() ?? '',
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _sections.add({'title': '', 'content': ''})),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Add Section'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveWebsite,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        'Save Website',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoCard(context),
          ],
        ),
      ),
    );
  }

  String get _prettyUrl {
    final slug = _slugController.text.trim().toLowerCase();
    return slug.isEmpty
        ? 'https://churchonapp.com/church/${widget.tenantId}'
        : 'https://churchonapp.com/c/$slug';
  }

  Widget _buildInfoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF7A5C00)),
              const SizedBox(width: 8),
              const Text(
                'How it works',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your website is available at:\n'
            '$_prettyUrl\n\n'
            'Once published, anyone with this link can view your church or '
            'bookshop profile — no app login needed. Share it on social '
            'media, business cards, and flyers. WhatsApp link previews show '
            'your banner, title and about text automatically.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String copyValue,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(LucideIcons.copy, size: 16),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: copyValue));
              if (context.mounted) {
                PremiumToast.showInfo(context, 'Link copied!');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker({
    required String label,
    required String? url,
    required bool uploading,
    required VoidCallback onPick,
  }) {
    final hasImage = url != null && url.isNotEmpty;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 84,
            height: 56,
            child: uploading
                ? Container(
                    color: Colors.grey.shade200,
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : hasImage
                    ? AppImage(url, fit: BoxFit.cover)
                    : Container(
                        color: Colors.grey.shade200,
                        child: Icon(
                          Icons.image_outlined,
                          color: Colors.grey.shade400,
                        ),
                      ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: uploading ? null : onPick,
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text('Upload'),
                  ),
                  if (hasImage)
                    TextButton(
                      onPressed: () => setState(() {
                        if (url == _bannerUrl) {
                          _bannerUrl = null;
                        } else {
                          _logoUrl = null;
                        }
                      }),
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage(String kind) async {
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
        _uploadingBanner = true;
      } else {
        _uploadingLogo = true;
      }
    });
    try {
      final file = File(picked.path);
      final folder = kind == 'banner' ? 'church-website-banners' : 'church-website-logos';
      final fileName =
          '${widget.tenantId}-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await ref
          .read(r2ServiceProvider)
          .uploadFile(file, '$folder/$fileName');
      if (url == null) {
        if (mounted) {
          PremiumToast.showError(context, 'Upload failed. Please try again.');
        }
        return;
      }
      setState(() {
        if (kind == 'banner') {
          _bannerUrl = url;
        } else {
          _logoUrl = url;
        }
      });
    } catch (e) {
      if (mounted) {
        PremiumToast.showError(context, AppErrorView.friendlyMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (kind == 'banner') {
            _uploadingBanner = false;
          } else {
            _uploadingLogo = false;
          }
        });
      }
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    IconData? icon,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon != null ? Icon(icon) : null,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _getSocialIcon(String platform) {
    switch (platform) {
      case 'facebook':
        return const Icon(Icons.facebook, color: Colors.blue);
      case 'instagram':
        return const Icon(Icons.camera_alt, color: Colors.purple);
      case 'twitter':
        return const Icon(Icons.language, color: Colors.lightBlue);
      case 'youtube':
        return const Icon(Icons.youtube_searched_for, color: Colors.red);
      default:
        return const Icon(Icons.link);
    }
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.green;
    }
  }

  void _showColorPicker() {
    const colors = [
      '#1B5E20', '#0D47A1', '#B71C1C', '#4A148C',
      '#E65100', '#006064', '#880E4F', '#1A237E',
      '#33691E', '#BF360C', '#004D40', '#311B92',
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose Color',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.map((hex) {
                final color = _parseColor(hex);
                final isSelected = hex == _primaryColor;
                return GestureDetector(
                  onTap: () {
                    setState(() => _primaryColor = hex);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveWebsite() async {
    if (_titleController.text.trim().isEmpty) {
      PremiumToast.showError(context, 'Title is required');
      return;
    }
    final slug = _slugController.text.trim().toLowerCase();
    final validSlug = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
    if (slug.isNotEmpty && !validSlug.hasMatch(slug)) {
      PremiumToast.showError(
        context,
        'Slug can only contain lowercase letters, numbers and dashes.',
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final service = ref.read(churchWebsiteServiceProvider);
      await service.saveWebsite(
        tenantId: widget.tenantId,
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        aboutText: _aboutController.text.trim(),
        logoUrl: _logoUrl,
        bannerUrl: _bannerUrl,
        contactPhone: _phoneController.text.trim(),
        contactEmail: _emailController.text.trim(),
        address: _addressController.text.trim(),
        primaryColor: _primaryColor,
        serviceTimes: _serviceTimes,
        socialLinks: _socialLinks,
        sections: _sections
            .where((s) =>
                (s['title']?.toString().trim().isNotEmpty ?? false) ||
                (s['content']?.toString().trim().isNotEmpty ?? false))
            .map((s) => {
                  'title': s['title']?.toString().trim() ?? '',
                  'content': s['content']?.toString().trim() ?? '',
                })
            .toList(),
        slug: slug.isEmpty ? null : slug,
      );

      if (mounted) {
        PremiumToast.showSuccess(context, 'Website saved!');
      }
    } catch (e) {
      if (mounted) {
        PremiumToast.showError(context, 'Error saving: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _togglePublish(bool publish) async {
    final service = ref.read(churchWebsiteServiceProvider);
    await service.togglePublish(widget.tenantId, publish);
    setState(() => _isPublished = publish);

    if (mounted) {
      PremiumToast.showInfo(
        context,
        publish ? 'Website published!' : 'Website unpublished',
      );
    }
  }

  void _previewWebsite() {
    final uri = Uri.parse(_prettyUrl);
    canLaunchUrl(uri).then((canLaunch) {
      if (canLaunch) {
        launchUrl(uri, mode: LaunchMode.inAppWebView);
      } else {
        if (mounted) {
          PremiumToast.showInfo(context, 'Preview URL: $_prettyUrl');
        }
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _aboutController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _slugController.dispose();
    super.dispose();
  }
}