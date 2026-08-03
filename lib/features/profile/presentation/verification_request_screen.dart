import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/profile_provider.dart';

class VerificationRequestScreen extends ConsumerStatefulWidget {
  const VerificationRequestScreen({super.key});

  @override
  ConsumerState<VerificationRequestScreen> createState() => _VerificationRequestScreenState();
}

class _VerificationRequestScreenState extends ConsumerState<VerificationRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _isSubmitting = false;
  String? _idDocumentPath;
  String? _existingStatus;

  @override
  void initState() {
    super.initState();
    _loadExistingRequest();
    final profile = ref.read(profileProvider).value;
    if (profile != null) {
      _fullNameCtrl.text = profile.name;
      _roleCtrl.text = profile.role;
    }
  }

  Future<void> _loadExistingRequest() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final res = await Supabase.instance.client
        .from('verification_requests')
        .select('status')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (res != null && mounted) {
      setState(() => _existingStatus = res['status'] as String?);
    }
  }

  Future<void> _pickDocument() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1920, maxHeight: 1920);
    if (file != null) setState(() => _idDocumentPath = file.path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("Not authenticated");

      String? idDocumentUrl;
      if (_idDocumentPath != null) {
        final file = File(_idDocumentPath!);
        final fileName = "verification_${DateTime.now().millisecondsSinceEpoch}.jpg";
        await Supabase.instance.client.storage.from('avatars').upload('verification/$fileName', file);
        idDocumentUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl('verification/$fileName');
      }

      final profile = ref.read(profileProvider).value;
      await Supabase.instance.client.from('verification_requests').insert({
        'user_id': user.id,
        'tenant_id': profile?.tenantId,
        'full_name': _fullNameCtrl.text.trim(),
        'role': _roleCtrl.text.trim(),
        'reason': _reasonCtrl.text.trim(),
        'id_document_url': idDocumentUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Verification request submitted!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("REQUEST VERIFICATION", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
        foregroundColor: Colors.white,
      ),
      body: _existingStatus != null
          ? _buildStatusView()
          : _buildFormView(),
    );
  }

  Widget _buildStatusView() {
    final (Color color, String label, IconData icon) = switch (_existingStatus!) {
      'approved' => (Colors.green, "APPROVED", LucideIcons.checkCircle),
      'rejected' => (Colors.redAccent, "REJECTED", LucideIcons.xCircle),
      _ => (Colors.amber, "PENDING REVIEW", LucideIcons.clock),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 48),
            ),
            const SizedBox(height: 24),
            Text(label, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 12),
            Text(
              _existingStatus == 'approved'
                  ? "Your account has been verified. The blue checkmark will appear on your profile."
                  : _existingStatus == 'rejected'
                      ? "Your verification request was not approved. You can submit a new request."
                      : "Your verification request is being reviewed by our team.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            const SizedBox(height: 32),
            if (_existingStatus == 'rejected')
              ElevatedButton(
                onPressed: () => setState(() => _existingStatus = null),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, minimumSize: const Size(200, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                child: const Text("SUBMIT NEW REQUEST", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.badgeCheck, color: Colors.blueAccent, size: 32),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "Get verified to earn a blue checkmark on your profile, increasing trust and visibility in the community.",
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildField(_fullNameCtrl, "Full Name", Icons.person, required: true),
            const SizedBox(height: 20),
            _buildField(_roleCtrl, "Church Role", Icons.church, required: true),
            const SizedBox(height: 20),
            _buildField(_reasonCtrl, "Reason for Verification", Icons.edit_note, maxLines: 3),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _pickDocument,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _idDocumentPath != null ? Colors.green.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_idDocumentPath != null ? LucideIcons.checkCircle : LucideIcons.upload, color: _idDocumentPath != null ? Colors.green : Colors.white38, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      _idDocumentPath != null ? "ID Document Selected" : "Upload ID Document (Optional)",
                      style: TextStyle(color: _idDocumentPath != null ? Colors.green : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  disabledBackgroundColor: Colors.amber.withValues(alpha: 0.4),
                ),
                child: _isSubmitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text("SUBMIT REQUEST", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, {bool required = false, int maxLines = 1}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? "Required" : null : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.03),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.amber)),
      ),
    );
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _roleCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }
}
