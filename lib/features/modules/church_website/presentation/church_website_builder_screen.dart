import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

/// Church website builder service
class ChurchWebsiteService {
  final SupabaseClient _client;

  ChurchWebsiteService(this._client);

  /// Get church website
  Future<Map<String, dynamic>?> getChurchWebsite(String tenantId) async {
    final result = await _client
        .from('church_websites')
        .select()
        .eq('church_id', tenantId)
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
  }) async {
    final existing = await getChurchWebsite(tenantId);

    final data = {
      'church_id': tenantId,
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
        .update({'is_published': publish})
        .eq('church_id', tenantId);
  }

  /// Get website preview URL
  String getPreviewUrl(String churchSlug) {
    return 'https://churchonapp.com/church/$churchSlug';
  }
}

final churchWebsiteServiceProvider = Provider<ChurchWebsiteService>((ref) {
  return ChurchWebsiteService(Supabase.instance.client);
});

/// Church website builder screen
class ChurchWebsiteBuilderScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const ChurchWebsiteBuilderScreen({super.key, required this.tenantId});

  @override
  ConsumerState<ChurchWebsiteBuilderScreen> createState() =>
      _ChurchWebsiteBuilderScreenState();
}

class _ChurchWebsiteBuilderScreenState
    extends ConsumerState<ChurchWebsiteBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _aboutController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  String _primaryColor = '#1B5E20';
  bool _isPublished = false;
  bool _loading = true;
  bool _saving = false;

  // Service times
  final Map<String, String> _serviceTimes = {
    'Sunday': '',
    'Wednesday': '',
    'Friday': '',
  };

  // Social links
  final Map<String, String> _socialLinks = {
    'facebook': '',
    'instagram': '',
    'twitter': '',
    'youtube': '',
  };

  @override
  void initState() {
    super.initState();
    _loadWebsite();
  }

  Future<void> _loadWebsite() async {
    final service = ref.read(churchWebsiteServiceProvider);
    final website = await service.getChurchWebsite(widget.tenantId);

    if (website != null) {
      _titleController.text = website['title'] ?? '';
      _subtitleController.text = website['subtitle'] ?? '';
      _aboutController.text = website['about_text'] ?? '';
      _phoneController.text = website['contact_phone'] ?? '';
      _emailController.text = website['contact_email'] ?? '';
      _addressController.text = website['address'] ?? '';
      _primaryColor = website['primary_color'] ?? '#1B5E20';
      _isPublished = website['is_published'] ?? false;

      // Load service times
      final times = website['service_times'] as Map<String, dynamic>? ?? {};
      times.forEach((key, value) {
        _serviceTimes[key] = value?.toString() ?? '';
      });

      // Load social links
      final links = website['social_links'] as Map<String, dynamic>? ?? {};
      links.forEach((key, value) {
        _socialLinks[key] = value?.toString() ?? '';
      });
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Website Builder')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Website Builder'),
        actions: [
          // Preview button
          IconButton(
            icon: Icon(Icons.preview),
            onPressed: _previewWebsite,
          ),
          // Publish toggle
          Switch(
            value: _isPublished,
            onChanged: (value) => _togglePublish(value),
            activeThumbColor: Colors.green,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Header section
            _buildSection(
              'Header',
              [
                _buildTextField('Title', _titleController),
                _buildTextField('Subtitle', _subtitleController),
              ],
            ),
            // About section
            _buildSection(
              'About',
              [
                _buildTextField('About Your Church', _aboutController, maxLines: 5),
              ],
            ),
            // Contact section
            _buildSection(
              'Contact',
              [
                _buildTextField('Phone', _phoneController, icon: Icons.phone),
                _buildTextField('Email', _emailController, icon: Icons.email),
                _buildTextField('Address', _addressController, icon: Icons.location_on),
              ],
            ),
            // Color picker
            _buildSection(
              'Branding',
              [
                Row(
                  children: [
                    Text('Primary Color'),
                    Spacer(),
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
            // Service times
            _buildSection(
              'Service Times',
              _serviceTimes.entries.map((entry) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(entry.key, style: TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'e.g. 09:00 AM',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (value) => _serviceTimes[entry.key] = value,
                          controller: TextEditingController(text: entry.value),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            // Social links
            _buildSection(
              'Social Links',
              _socialLinks.entries.map((entry) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '${entry.key} URL',
                      prefixIcon: _getSocialIcon(entry.key),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => _socialLinks[entry.key] = value,
                    controller: TextEditingController(text: entry.value),
                  ),
                );
              }).toList(),
            ),
            // Save button
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveWebsite,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text('Save Website', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
            SizedBox(height: 16),
            // Info card
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: const Color(0xFF7A5C00)),
                      SizedBox(width: 8),
                      Text('How it works', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your church website will be available at:\n'
                    'churchonapp.com/church/[your-slug]\n\n'
                    'Share this link on social media, business cards, and flyers.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: EdgeInsets.only(bottom: 24),
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
          SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {int maxLines = 1, IconData? icon}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _getSocialIcon(String platform) {
    switch (platform) {
      case 'facebook':
        return Icon(Icons.facebook, color: Colors.blue);
      case 'instagram':
        return Icon(Icons.camera_alt, color: Colors.purple);
      case 'twitter':
        return Icon(Icons.language, color: Colors.lightBlue);
      case 'youtube':
        return Icon(Icons.youtube_searched_for, color: Colors.red);
      default:
        return Icon(Icons.link);
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
    final colors = [
      '#1B5E20', '#0D47A1', '#B71C1C', '#4A148C',
      '#E65100', '#006064', '#880E4F', '#1A237E',
      '#33691E', '#BF360C', '#004D40', '#311B92',
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Choose Color', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
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
                        ? Icon(Icons.check, color: Colors.white)
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
    setState(() => _saving = true);

    try {
      final service = ref.read(churchWebsiteServiceProvider);
      await service.saveWebsite(
        tenantId: widget.tenantId,
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        aboutText: _aboutController.text.trim(),
        contactPhone: _phoneController.text.trim(),
        contactEmail: _emailController.text.trim(),
        address: _addressController.text.trim(),
        primaryColor: _primaryColor,
        serviceTimes: _serviceTimes,
        socialLinks: _socialLinks,
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
    final tenantId = ref.read(profileProvider).value?.tenantId ?? 'demo';
    final previewUrl = 'https://churchonapp.com/site/$tenantId';
    final uri = Uri.parse(previewUrl);
    canLaunchUrl(uri).then((canLaunch) {
      if (canLaunch) {
        launchUrl(uri, mode: LaunchMode.inAppWebView);
      } else {
        if (mounted) PremiumToast.showInfo(context, 'Preview URL: $previewUrl');
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
    super.dispose();
  }
}
