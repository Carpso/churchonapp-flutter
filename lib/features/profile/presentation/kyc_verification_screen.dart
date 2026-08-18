import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';
import '../data/kyc_service.dart';

class KycVerificationScreen extends ConsumerStatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  ConsumerState<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends ConsumerState<KycVerificationScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _idFile;
  XFile? _selfieFile;
  Uint8List? _idPreviewBytes;
  Uint8List? _selfiePreviewBytes;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _retrieveLostCaptures();
  }

  /// Recovers photos captured by the system camera app if Android killed
  /// this activity while the camera was open (common cause of "not capturing").
  Future<void> _retrieveLostCaptures() async {
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty || response.file == null) return;
      final file = response.file!;
      if (!mounted) return;
      setState(() {
        _selfieFile ??= file;
        _idFile ??= file;
      });
    } catch (e) {
      debugPrint('Lost capture recovery failed: $e');
    }
  }

  Future<Uint8List?> _readBytes(XFile file) async {
    try {
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('Failed to read picked file bytes: $e');
      return null;
    }
  }

  Future<void> _pickDocument() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1920, maxHeight: 1920);
      if (file != null && mounted) {
        setState(() {
          _idFile = file;
          _idPreviewBytes = null;
        });
        final bytes = await _readBytes(file);
        if (bytes != null && mounted) setState(() => _idPreviewBytes = bytes);
      } else if (mounted) {
        _snack("Document selection cancelled.", Colors.orange);
      }
    } catch (e) {
      if (mounted) {
        _snack("Error picking document: $e", Colors.red);
      }
    }
  }

  Future<void> _takeSelfie() async {
    // Some OEMs require the camera permission to be granted explicitly
    // before the system camera intent will return a photo.
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) _snack("Camera permission is required to take a selfie.", Colors.orange);
      return;
    }
    try {
      final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 512, maxHeight: 512);
      if (file != null && mounted) {
        setState(() {
          _selfieFile = file;
          _selfiePreviewBytes = null;
        });
        final bytes = await _readBytes(file);
        if (bytes != null && mounted) setState(() => _selfiePreviewBytes = bytes);
      } else if (mounted) {
        _snack("Selfie capture cancelled or camera unavailable.", Colors.orange);
      }
    } catch (e) {
      if (mounted) {
        _snack("Error taking selfie: $e", Colors.red);
      }
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _submit() async {
    if (_idFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please upload an ID document first"), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final service = ref.read(kycServiceProvider);
      final idBytes = await _idFile!.readAsBytes();
      await service.submitDocumentBytes(bytes: idBytes, documentType: 'national_id');
      if (_selfieFile != null) {
        final selfieBytes = await _selfieFile!.readAsBytes();
        await service.submitSelfieBytes(bytes: selfieBytes);
      }
      ref.invalidate(kycStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Documents submitted for verification!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(kycStatusProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text("TRUST & IDENTITY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(
                statusAsync.value == KycStatus.verified ? LucideIcons.shieldCheck : LucideIcons.shield,
                color: statusAsync.value == KycStatus.verified ? Colors.green : Colors.amber, size: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              statusAsync.when(
                data: (s) {
                  switch (s) {
                    case KycStatus.verified: return "VERIFIED";
                    case KycStatus.pending: return "PENDING REVIEW";
                    case KycStatus.rejected: return "REJECTED";
                    case KycStatus.unverified: return "UNVERIFIED";
                  }
                },
                loading: () => "LOADING...",
                error: (_, __) => "UNVERIFIED",
              ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 12),
            const Text(
              "Verify your identity to increase your withdrawal limits, secure your Coins, and participate in executive ministry roles.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 48),
            _buildUploadStep(
              step: "Step 1: ID Submission",
              desc: "Upload National ID, Passport, or Driver's License",
              icon: LucideIcons.fileText,
              file: _idFile,
              previewBytes: _idPreviewBytes,
              onTap: _pickDocument,
            ),
            const SizedBox(height: 16),
            _buildUploadStep(
              step: "Step 2: Live Selfie",
              desc: "Take a quick selfie for verification",
              icon: LucideIcons.camera,
              file: _selfieFile,
              previewBytes: _selfiePreviewBytes,
              onTap: _takeSelfie,
            ),
            const SizedBox(height: 16),
            _buildStep(
              "Step 3: Church Confirmation",
              "Confirmed by your local parish administrator",
              LucideIcons.church,
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 64),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text("START VERIFICATION", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadStep({required String step, required String desc, required IconData icon, XFile? file, Uint8List? previewBytes, VoidCallback? onTap}) {
    final captured = file != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: captured ? Colors.green.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: captured ? Colors.green.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            if (captured && kIsWeb && previewBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  previewBytes,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  cacheWidth: 112,
                  cacheHeight: 112,
                  errorBuilder: (_, __, ___) => Icon(icon, color: Colors.green, size: 24),
                ),
              )
            else if (captured && !kIsWeb)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(file.path),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  cacheWidth: 112,
                  cacheHeight: 112,
                  errorBuilder: (_, __, ___) => Icon(icon, color: Colors.green, size: 24),
                ),
              )
            else
              Icon(captured ? LucideIcons.checkCircle : icon, color: captured ? Colors.green : Colors.amber, size: 24),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                  Text(captured ? "Captured — tap to retake" : desc, style: TextStyle(color: captured ? Colors.green : Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Icon(captured ? LucideIcons.check : LucideIcons.circle, color: captured ? Colors.green : Colors.white12, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String title, String desc, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 24),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          const Icon(LucideIcons.circle, color: Colors.white12, size: 20),
        ],
      ),
    );
  }
}
