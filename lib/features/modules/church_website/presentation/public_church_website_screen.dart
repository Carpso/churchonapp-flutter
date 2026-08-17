import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/widgets/app_image.dart';

/// Public church website page — rendered for the shared URLs
/// `https://churchonapp.com/church/<churchId>` and
/// `https://churchonapp.com/site/<tenantId>`.
///
/// Works WITHOUT login: the `church_websites` RLS policy exposes rows where
/// `is_published = true` to the anon role, so anyone with the link can view
/// a published church website.
class PublicChurchWebsiteScreen extends ConsumerStatefulWidget {
  final String churchId;
  final String? slug;

  const PublicChurchWebsiteScreen({
    super.key,
    required this.churchId,
    this.slug,
  });

  @override
  ConsumerState<PublicChurchWebsiteScreen> createState() =>
      _PublicChurchWebsiteScreenState();
}

class _PublicChurchWebsiteScreenState
    extends ConsumerState<PublicChurchWebsiteScreen> {
  Map<String, dynamic>? _website;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWebsite();
  }

  Future<void> _loadWebsite() async {
    try {
      final client = Supabase.instance.client;
      Map<String, dynamic>? result;
      if (widget.slug != null && widget.slug!.isNotEmpty) {
        result = await client
            .from('church_websites')
            .select()
            .eq('slug', widget.slug!.toLowerCase())
            .maybeSingle();
      } else {
        result = await client
            .from('church_websites')
            .select()
            .eq('church_id', widget.churchId)
            .maybeSingle();
      }
      if (result == null) {
        setState(() {
          _error =
              'No published website found for this church. Ask the church to publish it from the Church On App Website Builder.';
        });
      } else {
        setState(() => _website = result);
        // Fire-and-forget anonymous view counter.
        try {
          await client.rpc('increment_website_view', params: {
            'p_website_id': result['id'],
          });
        } catch (_) {}
      }
    } catch (e) {
      setState(() {
        _error = 'Could not load this church website. Please try again later.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (e) {
      return const Color(0xFFFFDA03);
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildWebsite(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.church, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Website not available',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFDA03),
                foregroundColor: Colors.black,
              ),
              onPressed: () => _openLink('https://churchonapp.com'),
              child: const Text('Visit Church On App'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebsite() {
    final website = _website!;
    final title = website['title']?.toString() ?? 'Our Church';
    final subtitle = website['subtitle']?.toString() ?? '';
    final about = website['about_text']?.toString() ?? '';
    final logoUrl = website['logo_url']?.toString() ?? '';
    final bannerUrl = website['banner_url']?.toString() ?? '';
    final phone = website['contact_phone']?.toString() ?? '';
    final email = website['contact_email']?.toString() ?? '';
    final address = website['address']?.toString() ?? '';
    final accent = _parseColor(website['primary_color']?.toString() ?? '');

    final serviceTimes = (website['service_times'] as Map<String, dynamic>?) ?? {};
    final socialLinks = (website['social_links'] as Map<String, dynamic>?) ?? {};
    final socials = <MapEntry<String, dynamic>>[];
    for (final entry in socialLinks.entries) {
      final v = entry.value?.toString() ?? '';
      if (v.isNotEmpty) socials.add(entry);
    }

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: bannerUrl.isEmpty ? 140 : 220,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            background: bannerUrl.isEmpty
                ? Container(
                    color: accent,
                    alignment: Alignment.center,
                    child: logoUrl.isEmpty
                        ? const Icon(Icons.church, size: 72, color: Colors.white70)
                        : AppImage(
                            logoUrl,
                            width: 96,
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      AppImage(bannerUrl, fit: BoxFit.cover),
                      Container(
                        color: Colors.black.withValues(alpha: 0.35),
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            if (logoUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AppImage(logoUrl, width: 56, height: 56, fit: BoxFit.cover),
                              ),
                            if (logoUrl.isNotEmpty) const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                                    ),
                                  ),
                                  if (subtitle.isNotEmpty)
                                    Text(
                                      subtitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bannerUrl.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              if (about.isNotEmpty) ...[
                const SizedBox(height: 24),
                _sectionTitle('About Us'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(about, style: const TextStyle(fontSize: 14, height: 1.5)),
                ),
              ],
              ..._buildCustomSections(website['sections']),
              if (serviceTimes.isNotEmpty) ...[
                const SizedBox(height: 24),
                _sectionTitle('Service Times'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: serviceTimes.entries
                        .where((e) => (e.value?.toString() ?? '').isNotEmpty)
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(e.value.toString(), style: TextStyle(color: Colors.grey.shade700)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
              if (phone.isNotEmpty || email.isNotEmpty || address.isNotEmpty) ...[
                const SizedBox(height: 24),
                _sectionTitle('Contact'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      if (phone.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.phone, color: Color(0xFF7A5C00)),
                          title: Text(phone),
                          onTap: () => _openLink('tel:$phone'),
                        ),
                      if (email.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.email, color: Color(0xFF7A5C00)),
                          title: Text(email),
                          onTap: () => _openLink('mailto:$email'),
                        ),
                      if (address.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.location_on, color: Color(0xFF7A5C00)),
                          title: Text(address),
                        ),
                    ],
                  ),
                ),
              ],
              if (socials.isNotEmpty) ...[
                const SizedBox(height: 24),
                _sectionTitle('Follow Us'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 12,
                    children: socials.map((e) {
                      IconData icon;
                      Color color;
                      switch (e.key) {
                        case 'facebook':
                          icon = Icons.facebook;
                          color = const Color(0xFF1877F2);
                        case 'instagram':
                          icon = Icons.camera_alt;
                          color = const Color(0xFFE1306C);
                        case 'twitter':
                          icon = Icons.language;
                          color = const Color(0xFF1DA1F2);
                        case 'youtube':
                          icon = Icons.play_circle_fill;
                          color = const Color(0xFFFF0000);
                        default:
                          icon = Icons.link;
                          color = Colors.grey;
                      }
                      return IconButton(
                        icon: Icon(icon, color: color),
                        onPressed: () => _openLink(e.value.toString()),
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                color: const Color(0xFFFFDA03),
                child: Column(
                  children: [
                    const Text(
                      'Get the Church On App',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Giving, events, sermons, radio & more — from this church and thousands across Zambia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.black54),
                      ),
                      onPressed: () => _openLink('https://churchonapp.com'),
                      child: const Text('Download the App'),
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

  List<Widget> _buildCustomSections(dynamic sectionsRaw) {
    if (sectionsRaw is! List || sectionsRaw.isEmpty) return const [];
    final widgets = <Widget>[];
    for (final raw in sectionsRaw) {
      if (raw is! Map) continue;
      final title = raw['title']?.toString().trim() ?? '';
      final content = raw['content']?.toString().trim() ?? '';
      if (title.isEmpty && content.isEmpty) continue;
      widgets.add(const SizedBox(height: 24));
      if (title.isNotEmpty) {
        widgets.add(_sectionTitle(title));
        widgets.add(const SizedBox(height: 10));
      }
      if (content.isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              content,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF7A5C00)),
      ),
    );
  }
}