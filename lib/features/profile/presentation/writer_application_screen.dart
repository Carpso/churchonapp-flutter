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
            Text('Become a Writer', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Submit your application to become an approved writer. You\'ll be able to publish Kingdom News articles.', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 24),
            TextFormField(controller: _nameC, decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder()), validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 2) return 'Min 2 characters';
              return null;
            }),
            const SizedBox(height: 12),
            TextFormField(controller: _emailC, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()), keyboardType: TextInputType.emailAddress, validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            }),
            const SizedBox(height: 12),
            TextFormField(controller: _phoneC, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()), keyboardType: TextInputType.phone, validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.replaceAll(RegExp(r'\D'), '').length < 10) return 'Min 10 digits';
              return null;
            }),
            const SizedBox(height: 12),
            TextFormField(controller: _reasonC, decoration: const InputDecoration(labelText: 'Why do you want to write? *', border: OutlineInputBorder()), maxLines: 3, validator: (v) => v?.isEmpty == true ? 'Required' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _samplesC, decoration: const InputDecoration(labelText: 'Link to writing samples (optional)', border: OutlineInputBorder(), hintText: 'https://...'), keyboardType: TextInputType.url),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: const Icon(LucideIcons.send),
                label: Text(_isSubmitting ? 'Submitting...' : 'Submit Application'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
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
