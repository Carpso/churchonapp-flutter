import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_io/io.dart';
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
  File? _selectedFile;
  final _titleController = TextEditingController();
  final _speakerController = TextEditingController();

  final List<String> _folders = ['klips', 'sermons', 'marketplace'];

  Future<void> _pickFile() async {
    final picker = ImagePicker();
    try {
      if (_mediaType == 'image') {
        final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (file != null && mounted) {
          setState(() => _selectedFile = File(file.path));
        }
      } else {
        final file = await picker.pickVideo(source: ImageSource.gallery);
        if (file != null && mounted) {
          setState(() => _selectedFile = File(file.path));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pick error: $e")));
      }
    }
  }

  Future<void> _startUpload() async {
    if (_titleController.text.isEmpty || _selectedFile == null) {
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

      final ext = _selectedFile!.path.split('.').last.toLowerCase();
      final fileName = "${DateTime.now().millisecondsSinceEpoch}_${_titleController.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}.$ext";
      final publicUrl = await r2Service.uploadFile(_selectedFile!, "$_targetFolder/$fileName");

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
      } else {
        // Marketplace asset: stored on R2 for use in product listings.
        if (mounted) _showAssetUrlDialog(publicUrl);
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

  void _showAssetUrlDialog(String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.green, size: 60),
            const SizedBox(height: 20),
            const Text("Asset Uploaded!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("This image is stored on R2. Use its URL when creating a product in the Marketplace.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(url, style: const TextStyle(fontSize: 11, color: Colors.black87)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("DONE")),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
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
            const Text("Your file has been saved to Cloudflare R2 and indexed in the Database.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
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
            const Text("All assets are served via Cloudflare R2 Edge", style: TextStyle(color: Colors.grey, fontSize: 12)),
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
            _selectedFile != null ? _selectedFile!.path.split('\\').last.split('/').last : (isImage ? "Supports JPG, PNG" : "Supports MP4, MKV"),
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
        Text("UPLOADING TO R2: ${(_progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}