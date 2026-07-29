import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/admin/data/writer_approval_service.dart';

class WriterApplicationScreen extends ConsumerStatefulWidget {
  const WriterApplicationScreen({super.key});

  @override
  ConsumerState<WriterApplicationScreen> createState() => _WriterApplicationScreenState();
}

class _WriterApplicationScreenState extends ConsumerState<WriterApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  final _emailC = TextEditingController();
  final _phoneC = TextEditingController();
  final _reasonC = TextEditingController();
  final _samplesC = TextEditingController();
  bool _isSubmitting = false;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _nameC.dispose();
    _emailC.dispose();
    _phoneC.dispose();
    _reasonC.dispose();
    _samplesC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existingApp = ref.watch(_myWriterApplicationProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Apply as Writer')),
      body: existingApp.when(
        data: (app) {
          if (app != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      app.status == 'approved' ? LucideIcons.checkCircle : app.status == 'rejected' ? LucideIcons.xCircle : LucideIcons.clock,
                      size: 80,
                      color: app.status == 'approved' ? Colors.green : app.status == 'rejected' ? Colors.red : Colors.amber,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      app.status == 'approved' ? 'Approved!' : app.status == 'rejected' ? 'Not Approved' : 'Pending Review',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      app.status == 'approved'
                          ? 'Congratulations! You can now publish articles.'
                          : app.status == 'rejected'
                              ? 'Reason: ${app.rejectionReason ?? "Not specified"}'
                              : 'Your application is being reviewed. You\'ll be notified when it\'s approved.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return _buildForm(theme);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.penTool, color: Colors.white, size: 32),
                  const SizedBox(height: 12),
                  const Text('Become a Writer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(
                    'Submit your application to become an approved writer for News.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionLabel('Personal Information'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameC,
              textCapitalization: TextCapitalization.words,
              decoration: _inputDecoration('Full Name *', LucideIcons.user),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length < 2) return 'Min 2 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailC,
              decoration: _inputDecoration('Email *', LucideIcons.mail),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneC,
              decoration: _inputDecoration('Phone *', LucideIcons.phone),
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.replaceAll(RegExp(r'\D'), '').length < 10) return 'Min 10 digits';
                return null;
              },
            ),
            const SizedBox(height: 24),
            Container(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 24),
            _sectionLabel('Writing Background'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reasonC,
              decoration: _inputDecoration('Why do you want to write? *', LucideIcons.fileText),
              maxLines: 4,
              maxLength: 500,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _samplesC,
              decoration: _inputDecoration('Writing samples link (optional)', LucideIcons.link),
              keyboardType: TextInputType.url,
              maxLength: 200,
            ),
            const SizedBox(height: 24),
            Container(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 24),
            Row(
              children: [
                Checkbox(
                  value: _agreedToTerms,
                  onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                  activeColor: theme.primaryColor,
                ),
                Expanded(
                  child: Text(
                    'I confirm that the information provided is accurate and I agree to the writer guidelines.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: const Icon(LucideIcons.send),
                label: Text(_isSubmitting ? 'Submitting...' : 'Submit Application'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: Colors.grey.shade800,
        letterSpacing: 0.3,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Future<void> _submit() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the terms before submitting.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(writerApprovalServiceProvider).applyAsWriter(
        fullName: _nameC.text.trim(),
        email: _emailC.text.trim(),
        phone: _phoneC.text.trim(),
        reason: _reasonC.text.trim(),
        writingSamplesUrl: _samplesC.text.trim(),
      );
      ref.invalidate(_myWriterApplicationProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Application submitted! Awaiting approval.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

final _myWriterApplicationProvider = FutureProvider<WriterApplication?>((ref) async {
  return ref.read(writerApprovalServiceProvider).getMyApplication();
});
