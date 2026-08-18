import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class FlyerStudioScreen extends ConsumerStatefulWidget {
  const FlyerStudioScreen({super.key});

  @override
  ConsumerState<FlyerStudioScreen> createState() => _FlyerStudioScreenState();
}

class _FlyerStudioScreenState extends ConsumerState<FlyerStudioScreen> {
  final GlobalKey _flyerKey = GlobalKey();
  final _titleController = TextEditingController(text: "SUNDAY PRAISE EXPLOSION");
  final _speakerController = TextEditingController(text: "Pastor Matthew Chanda");
  final _timeController = TextEditingController(text: "Sunday at 09:00 AM");
  final _venueController = TextEditingController(text: "St. Peters Cathedral, Lusaka");

  bool _isSharing = false;
  bool _isPosting = false;

  String _selectedCategory = "Event Invitation";
  String _selectedTemplate = "Royal Gold"; // Royal Gold, Midnight Purple, Sacred White, Forest Green

  final List<String> _categories = [
    "Sermon Series",
    "Event Invitation",
    "Daily Devotion",
    "Prayer Night",
    "Sunday Celebration",
    "Midweek Service",
    "Youth Conference",
    "Women's Meeting",
  ];
  final List<String> _templates = ["Royal Gold", "Midnight Purple", "Sacred White", "Forest Green"];

  @override
  void dispose() {
    _titleController.dispose();
    _speakerController.dispose();
    _timeController.dispose();
    _venueController.dispose();
    super.dispose();
  }

  String get _announcementText {
    return """
========================================
🌟 CHURCH ON APP - FLYER ANNOUNCEMENT 🌟
========================================
Category: $_selectedCategory
Title: ${_titleController.text.toUpperCase()}
Speaker: ${_speakerController.text}
Time: ${_timeController.text}
Venue: ${_venueController.text}

✨ "Connecting Churches Through Technology" ✨
========================================
""";
  }

  Future<Uint8List> _renderFlyerPng() async {
    final boundary = _flyerKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _generateFlyer() async {
    await Clipboard.setData(ClipboardData(text: _announcementText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Flyer details compiled & copied to clipboard!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _shareFlyer() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final png = await _renderFlyerPng();
      final dir = await getTemporaryDirectory();
      final file = XFile.fromData(
        png,
        path: '${dir.path}/church_on_app_flyer.png',
        mimeType: 'image/png',
        name: 'church_on_app_flyer.png',
      );
      await SharePlus.instance.share(ShareParams(
        files: [file],
        text: _announcementText.trim(),
        sharePositionOrigin: Rect.fromLTWH(0, 0, 600, 800),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Share error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _postToConnect() async {
    if (_isPosting) return;
    setState(() => _isPosting = true);
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      final tenant = ref.read(currentTenantProvider);
      if (user == null) {
        throw Exception("Not signed in");
      }
      final png = await _renderFlyerPng();
      final r2 = ref.read(r2ServiceProvider);
      final fileName = 'flyers/${DateTime.now().millisecondsSinceEpoch}_${user.id}.png';
      final url = await r2.uploadBytes(png, fileName, contentType: 'image/png');
      if (url == null) {
        throw Exception("R2 upload failed");
      }
      final content = "${_titleController.text.toUpperCase()}\n$_selectedCategory • ${_timeController.text} • ${_venueController.text}\n#ChurchOnApp";
      await client.from('social_posts').insert({
        'user_id': user.id,
        'content': content,
        'media_url': url,
        'media_type': 'image',
        'images': [url],
        'category': _selectedCategory,
        'tenant_id': tenant?.id,
        'church_id': tenant?.id,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Flyer posted to Connect feed!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Post error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  // Gradient helper for backgrounds
  LinearGradient _getTemplateGradient() {
    switch (_selectedTemplate) {
      case "Midnight Purple":
        return const LinearGradient(
          colors: [Color(0xFF2E0854), Color(0xFF140026)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case "Sacred White":
        return const LinearGradient(
          colors: [Color(0xFFF9F9FB), Color(0xFFE5E7EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case "Forest Green":
        return const LinearGradient(
          colors: [Color(0xFF0F5132), Color(0xFF072214)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case "Royal Gold":
      default:
        return const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  Color _getTemplateAccentColor() {
    switch (_selectedTemplate) {
      case "Sacred White":
        return const Color(0xFFB45309); // Dark amber/gold
      case "Forest Green":
        return const Color(0xFFFBBF24); // Warm gold
      case "Midnight Purple":
        return const Color(0xFFEC4899); // Electric Pink
      case "Royal Gold":
      default:
        return const Color(0xFFD97706); // Amber Gold
    }
  }

  Color _getTemplateTextColor() {
    return _selectedTemplate == "Sacred White" ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _getTemplateAccentColor();
    final textColor = _getTemplateTextColor();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Flyer Studio", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview Section
            const Text("PREVIEW BANNER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            Center(
              child: RepaintBoundary(
                key: _flyerKey,
                child: AspectRatio(
                  aspectRatio: 1.2,
                  child: Container(
                  decoration: BoxDecoration(
                    gradient: _getTemplateGradient(),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 8))],
                    border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 2),
                  ),
                  child: Stack(
                    children: [
                      // Background Graphic elements
                      Positioned(
                        right: -30,
                        top: -30,
                        child: CircleAvatar(
                          radius: 80,
                          backgroundColor: accentColor.withValues(alpha: 0.08),
                        ),
                      ),
                      Positioned(
                        left: -50,
                        bottom: -50,
                        child: CircleAvatar(
                          radius: 100,
                          backgroundColor: accentColor.withValues(alpha: 0.05),
                        ),
                      ),
                      // Core details
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    _selectedCategory.toUpperCase(),
                                    style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1),
                                  ),
                                ),
                                Image.asset(
                                  'assets/app_logo.png',
                                  width: 25,
                                  height: 25,
                                  errorBuilder: (_, __, ___) => Icon(LucideIcons.flame, color: accentColor, size: 20),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _titleController.text.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: textColor,
                                    letterSpacing: 1.2,
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "FEATURING:",
                                  style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                ),
                                Text(
                                  _speakerController.text,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.9)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(color: Colors.white24, height: 16),
                                Row(
                                  children: [
                                    Icon(LucideIcons.calendar, color: accentColor, size: 13),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _timeController.text,
                                        style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Icon(LucideIcons.mapPin, color: accentColor, size: 13),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _venueController.text,
                                        style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
            const SizedBox(height: 30),

            // Design Configuration Controls
            const Text("STUDIO CONTROLS", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            // Select Category
            const Text("Banner Category", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 15),

            // Select Template Theme
            const Text("Color Theme", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: _templates.map((t) {
                final isSel = _selectedTemplate == t;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTemplate = t),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSel ? theme.primaryColor : Colors.white,
                        border: Border.all(color: isSel ? theme.primaryColor : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        t.split(' ')[1],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSel ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Inputs
            const Text("Flyer Headline Text", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 15),

            const Text("Keynote Speaker Name", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _speakerController,
              decoration: InputDecoration(
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 15),

            const Text("Date & Time Details", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _timeController,
              decoration: InputDecoration(
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 15),

            const Text("Location / Venue Details", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _venueController,
              decoration: InputDecoration(
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 30),

            // Actions
            ElevatedButton.icon(
              onPressed: _generateFlyer,
              icon: const Icon(LucideIcons.checkCircle),
              label: const Text("GENERATE & COPY ANNOUNCEMENT"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSharing ? null : _shareFlyer,
                    icon: _isSharing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.share2),
                    label: const Text("SHARE IMAGE"),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPosting ? null : _postToConnect,
                    icon: _isPosting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.send),
                    label: const Text("POST TO CONNECT"),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "SHARE IMAGE sends the flyer to WhatsApp, email or any app — POST TO CONNECT publishes it to your church's Connect feed.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}