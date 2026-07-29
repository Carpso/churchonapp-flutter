import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import '../data/kyc_service.dart';

class KycVerificationScreen extends ConsumerStatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  ConsumerState<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends ConsumerState<KycVerificationScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _idFilePath;
  String? _selfiePath;
  bool _isSubmitting = false;

  Future<void> _pickDocument() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file != null) setState(() => _idFilePath = file.path);
  }

  Future<void> _takeSelfie() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (file != null) setState(() => _selfiePath = file.path);
  }

  Future<void> _submit() async {
    if (_idFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please upload an ID document first"), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final service = ref.read(kycServiceProvider);
      await service.submitDocument(filePath: _idFilePath!, documentType: 'national_id');
      if (_selfiePath != null) {
        await service.submitSelfie(filePath: _selfiePath!);
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
              filePath: _idFilePath,
              onTap: _pickDocument,
            ),
            const SizedBox(height: 16),
            _buildUploadStep(
              step: "Step 2: Live Selfie",
              desc: "Take a quick selfie for verification",
              icon: LucideIcons.camera,
              filePath: _selfiePath,
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

  Widget _buildUploadStep({required String step, required String desc, required IconData icon, String? filePath, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: filePath != null ? Colors.green.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: filePath != null ? Colors.green.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(filePath != null ? LucideIcons.checkCircle : icon, color: filePath != null ? Colors.green : Colors.amber, size: 24),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                  Text(filePath != null ? "Uploaded!" : desc, style: TextStyle(color: filePath != null ? Colors.green : Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Icon(filePath != null ? LucideIcons.check : LucideIcons.circle, color: filePath != null ? Colors.green : Colors.white12, size: 20),
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
