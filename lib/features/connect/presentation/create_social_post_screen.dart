import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_io/io.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/social_service.dart';
import '../data/testimony_service.dart';
import '../data/prayer_service.dart';
import '../data/user_activity_service.dart';
import '../../bible/data/bible_verse_service.dart';
import '../../../core/providers/profile_provider.dart';

class CreateSocialPostScreen extends ConsumerStatefulWidget {
  const CreateSocialPostScreen({super.key});

  @override
  ConsumerState<CreateSocialPostScreen> createState() => _CreateSocialPostScreenState();
}

class _CreateSocialPostScreenState extends ConsumerState<CreateSocialPostScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isPosting = false;
  List<File> _selectedImages = [];
  String _postType = "Social"; // "Social", "Testimony", "Prayer", "Daily Verse"

  Future<void> _pickImages(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      final picked = await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1080, maxHeight: 1080);
      if (picked != null) {
        setState(() => _selectedImages = [File(picked.path)]);
      }
    } else {
      final picked = await picker.pickMultiImage(imageQuality: 70);
      if (picked.isNotEmpty) {
        setState(() => _selectedImages = picked.map((p) => File(p.path)).toList());
      }
    }
  }

  Future<void> _handlePost() async {
    if (_controller.text.trim().isEmpty && _selectedImages.isEmpty) return;
    setState(() => _isPosting = true);
    
    try {
      List<String> uploadedUrls = [];

      if (_selectedImages.isNotEmpty) {
        final r2 = ref.read(r2ServiceProvider);
        int uploadFailed = 0;
        for (final image in _selectedImages) {
          final fileName = "social_${DateTime.now().millisecondsSinceEpoch}_${uploadedUrls.length}.jpg";
          final url = await r2.uploadFile(image, "social/$fileName");
          if (url != null) {
            uploadedUrls.add(url);
          } else {
            uploadFailed++;
          }
        }
        if (uploadFailed > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$uploadFailed image(s) failed to upload. ${uploadedUrls.isEmpty ? 'Posting without images.' : 'Posting with ${uploadedUrls.length} image(s).'}"),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      final mediaUrl = uploadedUrls.isNotEmpty ? uploadedUrls.first : null;
      if (_postType == "Social") {
        await ref.read(socialServiceProvider).createPost(
          content: _controller.text,
          mediaUrl: mediaUrl,
          images: uploadedUrls,
          mediaType: uploadedUrls.isNotEmpty ? 'image' : 'text',
        );
        ref.invalidate(socialPostsProvider);
      } else if (_postType == "Testimony") {
        await ref.read(testimonyServiceProvider).submitTestimony(
          _controller.text,
          mediaUrl,
        );
        ref.invalidate(testimonyStreamProvider);
      } else if (_postType == "Prayer") {
        await ref.read(prayerServiceProvider).submitPrayer(
          _controller.text,
          "general",
          "public",
          false,
        );
        ref.invalidate(prayerStreamProvider);
      } else if (_postType == "Daily Verse") {
        // Parse reference on first line and text on other lines
        final lines = _controller.text.trim().split('\n');
        final reference = lines.first.trim();
        final text = lines.length > 1 ? lines.sublist(1).join('\n').trim() : "Amen";

        await ref.read(bibleVerseServiceProvider).postDailyVerse(
          reference: reference,
          text: text,
        );
        ref.invalidate(dailyBibleVerseProvider);
      }
      
      final activity = ref.read(userActivityServiceProvider);
      if (_postType == "Social") {
        activity.logActivity(type: ActivityType.socialPosted, description: "Posted on Church Social", coinsEarned: 5);
      } else if (_postType == "Testimony") {
        activity.logActivity(type: ActivityType.testimonyShared, description: "Shared a testimony", coinsEarned: 10);
      } else if (_postType == "Prayer") {
        activity.logActivity(type: ActivityType.prayerPosted, description: "Posted a prayer request", coinsEarned: 3);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Posted successfully as $_postType!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Post failed: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  String get _hintText {
    switch (_postType) {
      case "Testimony":
        return "What miracle has God done today?";
      case "Prayer":
        return "What are we interceding for?";
      case "Daily Verse":
        return "Enter Reference on the first line, and scripture below:\n\nJeremiah 29:11\nFor I know the thoughts that I think toward you...";
      default:
        return "What is on your mind? Share an edifying word...";
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final types = ["Social", "Testimony", "Prayer"];
    // Add "Daily Verse" option for church leaders, employees, or admins
    final isLeaderOrAdmin = profile?.isAdminOrHigher == true || profile?.isLeadershipTeam == true || profile?.isEmployee == true;
    if (isLeaderOrAdmin && !types.contains("Daily Verse")) {
      types.add("Daily Verse");
    }

    final hasDraft = _controller.text.trim().isNotEmpty || _selectedImages.isNotEmpty || _isPosting;

    return PopScope(
      canPop: !hasDraft,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Discard Draft?"),
            content: const Text(
              "You have an unsaved post draft in progress. Discarding will erase your text and attached images.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("KEEP EDITING"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text("DISCARD DRAFT"),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Create $_postType", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _isPosting ? null : _handlePost,
            child: _isPosting 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("POST", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blue)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Builder(
                  builder: (context) {
                    final avatarUrl = profile?.avatarUrl;
                    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
                    final name = profile?.name ?? 'K';
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'K';
                    return CircleAvatar(
                      backgroundColor: const Color(0xFF1A1A1A),
                      backgroundImage: hasAvatar ? CachedNetworkImageProvider(avatarUrl) : null,
                      child: hasAvatar
                          ? null
                          : Text(
                              initial,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                    );
                  },
                ),
                const SizedBox(width: 15),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile?.name ?? "Partner", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("Posting to public feed", style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 15),
            // Pill Type Selector
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: types.length,
                itemBuilder: (context, index) {
                  final type = types[index];
                  final isSelected = _postType == type;
                  return GestureDetector(
                    onTap: () => setState(() => _postType = type),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.amber : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected ? Border.all(color: Colors.amber.shade700, width: 1) : null,
                      ),
                      child: Center(
                        child: Text(
                          type.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.black : Colors.grey.shade600,
                            fontSize: 10,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 30),
            if (_selectedImages.isNotEmpty)
              SizedBox(
                height: 120,
                child: Stack(
                  children: [
                    ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(image: FileImage(_selectedImages[index]), fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 4, right: 12,
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedImages.removeAt(index)),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: _hintText,
                  border: InputBorder.none,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black12))),
              child: Row(
                children: [
                  IconButton(icon: const Icon(LucideIcons.camera, color: Colors.blue), onPressed: () => _pickImages(ImageSource.camera)),
                  IconButton(icon: const Icon(LucideIcons.image, color: Colors.green), onPressed: () => _pickImages(ImageSource.gallery)),
                  IconButton(icon: const Icon(LucideIcons.mapPin, color: Colors.red), onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Location tag coming soon"), duration: Duration(seconds: 2)),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}


