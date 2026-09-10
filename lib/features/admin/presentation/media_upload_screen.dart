import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/r2_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class MediaUploadScreen extends ConsumerStatefulWidget {
  const MediaUploadScreen({super.key});

  @override
  ConsumerState<MediaUploadScreen> createState() => _MediaUploadScreenState();
}

class _MediaUploadScreenState extends ConsumerState<MediaUploadScreen> {
  bool _isUploading = false;
  double _progress = 0.0;
  String _targetFolder = 'klips';
  String _mediaType = 'video';
  XFile? _selectedFile;
  Uint8List? _selectedBytes;
  String? _selectedName;
  final _titleController = TextEditingController();
  final _speakerController = TextEditingController();

  final List<String> _folders = ['klips', 'sermons', 'marketplace'];

  Future<void> _pickFile() async {
    final picker = ImagePicker();
    try {
      XFile? file;
      if (_mediaType == 'image') {
        file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      } else {
        file = await picker.pickVideo(source: ImageSource.gallery);
      }
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        setState(() {
          _selectedFile = file;
          _selectedBytes = bytes;
          _selectedName = file!.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pick error: $e")));
      }
    }
  }

  Future<void> _startUpload() async {
    if (_titleController.text.isEmpty || _selectedFile == null || _selectedBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Title and File are required")));
      return;
    }
    if (_targetFolder == 'marketplace' && _mediaType != 'image') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Marketplace assets must be images")));
      return;
    }

    setState(() {
      _isUploading = true;
      _progress = 0.2;
    });

    try {
      final r2Service = ref.read(r2ServiceProvider);
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      final tenant = ref.read(currentTenantProvider);

      final originalName = _selectedName ?? _selectedFile!.name;
      final ext = originalName.split('.').last.toLowerCase();
      final contentType = _mediaType == 'image'
          ? (ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg')
          : (ext == 'mov' ? 'video/quicktime' : 'video/mp4');
      final fileName = "${DateTime.now().millisecondsSinceEpoch}_${_titleController.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}.$ext";
      // Use bytes path — works on web and mobile, avoids dart:io File on web.
      final publicUrl = await r2Service.uploadBytes(_selectedBytes!, "$_targetFolder/$fileName", contentType: contentType);

      if (publicUrl == null) {
        throw Exception("R2 Upload Failed");
      }
      setState(() => _progress = 0.8);

      final tenantId = tenant?.id;
      final churchId = tenant?.id;

      if (_targetFolder == 'klips') {
        await client.from('klips').insert({
          'user_id': user?.id,
          'user_name': user?.email,
          'title': _titleController.text,
          'video_url': publicUrl,
          'speaker': _speakerController.text.isEmpty ? 'Member' : _speakerController.text,
          'description': 'Uploaded via Media Manager',
          'thumbnail_url': '',
          'tenant_id': tenantId,
          'church_id': churchId,
        });
      } else if (_targetFolder == 'sermons') {
        await client.from('sermons').insert({
          'tenant_id': tenantId,
          'church_id': churchId,
          'title': _titleController.text,
          'speaker': _speakerController.text.isEmpty ? 'Church Ministry' : _speakerController.text,
          'preacher': _speakerController.text.isEmpty ? 'Church Ministry' : _speakerController.text,
          'video_url': _mediaType == 'video' ? publicUrl : null,
          'audio_url': null,
          'thumbnail_url': '',
          'is_live': false,
          'viewer_count': 0,
          'duration_minutes': 0,
          'category': 'Media Manager',
        });
        // Notify church members of new sermon (fire-and-forget)
        if (tenantId != null) _notifySermonPublished(client, tenantId, _titleController.text);
      } else {
        // Marketplace asset: stored securely for use in product listings.
        if (mounted) _showSuccessDialog(message: "Asset uploaded and will be available in your product listings.");
        setState(() => _progress = 1.0);
        if (mounted) setState(() => _isUploading = false);
        return;
      }

      setState(() => _progress = 1.0);
      if (mounted) _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSuccessDialog({String? message}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.green, size: 60),
            const SizedBox(height: 20),
            const Text("Upload Successful!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(message ?? "Your file has been saved securely and will appear after processing.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("GLORY TO GOD")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Media Manager"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Upload Content", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text("Secure media upload — your content is encrypted in transit", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 30),

            _buildInputLabel("MEDIA TYPE"),
            _buildTypeSelector(),

            const SizedBox(height: 20),
            _buildInputLabel("CONTENT TITLE"),
            _buildTextField(_titleController, "e.g. Sunday Morning Miracle"),

            const SizedBox(height: 20),
            _buildInputLabel("SPEAKER / AUTHOR"),
            _buildTextField(_speakerController, "e.g. Pastor John Doe"),

            const SizedBox(height: 25),
            _buildInputLabel("TARGET FOLDER"),
            _buildFolderSelector(),

            const SizedBox(height: 40),
            GestureDetector(
              onTap: _pickFile,
              child: _buildUploadZone(),
            ),

            const SizedBox(height: 50),
            if (_isUploading)
              _buildProgressIndicator()
            else
              ElevatedButton(
                onPressed: _startUpload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  minimumSize: const Size(double.infinity, 65),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: const Text("START SECURE UPLOAD", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    final types = [
      {'id': 'video', 'label': 'VIDEO'},
      {'id': 'image', 'label': 'IMAGE'},
    ];
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: types.length,
        itemBuilder: (context, index) {
          final isSelected = _mediaType == types[index]['id'];
          return GestureDetector(
            onTap: () => setState(() {
              _mediaType = types[index]['id'] as String;
              _selectedFile = null;
            }),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Text(
                  types[index]['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 5),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2, color: Colors.grey)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildFolderSelector() {
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _folders.length,
        itemBuilder: (context, index) {
          final isSelected = _targetFolder == _folders[index];
          return GestureDetector(
            onTap: () => setState(() {
              _targetFolder = _folders[index];
              _selectedFile = null;
            }),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Text(
                  _folders[index].toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUploadZone() {
    final isImage = _mediaType == 'image';
    final displayName = _selectedName ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(
            _selectedFile == null ? (isImage ? LucideIcons.image : LucideIcons.fileVideo) : LucideIcons.checkCircle,
            size: 50,
            color: _selectedFile == null ? Theme.of(context).primaryColor : Colors.green,
          ),
          const SizedBox(height: 20),
          const Text("TAP TO SELECT MEDIA", style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            _selectedFile != null ? displayName : (isImage ? "Supports JPG, PNG" : "Supports MP4, MKV"),
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: Colors.grey.shade200,
          color: Theme.of(context).primaryColor,
          minHeight: 12,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(height: 15),
        Text("Uploading: ${(_progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  /// Notify church members of new sermon (fire-and-forget).
  void _notifySermonPublished(SupabaseClient client, String tenantId, String title) {
    try {
      // Best-effort: find a few church member IDs and push to each
      client
          .from('profiles')
          .select('id')
          .eq('tenant_id', tenantId)
          .neq('id', client.auth.currentUser?.id ?? '')
          .limit(200)
          .then((members) {
        for (final m in (members as List)) {
          final uid = m['id']?.toString();
          if (uid == null) continue;
          try {
            client.functions.invoke('push-notifications', body: {
              'userId': uid,
              'title': 'New Sermon',
              'body': '"$title" has been published.',
              'type': 'sermon',
            });
          } catch (_) {}
        }
      });
    } catch (_) {}
  }
}