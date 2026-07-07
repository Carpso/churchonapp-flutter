import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BookshopOnboardingScreen extends ConsumerStatefulWidget {
  const BookshopOnboardingScreen({super.key});

  @override
  ConsumerState<BookshopOnboardingScreen> createState() => _BookshopOnboardingScreenState();
}

class _BookshopOnboardingScreenState extends ConsumerState<BookshopOnboardingScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  final _nameC = TextEditingController();
  final _descC = TextEditingController();
  final _contactC = TextEditingController();
  final _locationC = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nameC.dispose();
    _descC.dispose();
    _contactC.dispose();
    _locationC.dispose();
    super.dispose();
  }

  bool get _canProceedFromStep1 =>
      _nameC.text.trim().isNotEmpty && _descC.text.trim().isNotEmpty;

  bool get _canProceedFromStep2 =>
      _contactC.text.trim().isNotEmpty && _locationC.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.from('marketplace_items').insert({
        'name': _nameC.text.trim(),
        'description': _descC.text.trim(),
        'contact': _contactC.text.trim(),
        'location': _locationC.text.trim(),
        'category': 'bookshop',
        'vendor_id': Supabase.instance.client.auth.currentUser?.id,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bookshop created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('Set Up Bookshop'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: List.generate(3, (i) {
                final isActive = i <= _currentStep;
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isActive
                          ? theme.primaryColor
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentStep = i),
              children: [
                _buildStep1(theme),
                _buildStep2(theme),
                _buildStep3(theme),
              ],
            ),
          ),
          _buildBottomNav(theme),
        ],
      ),
    );
  }

  Widget _buildStepText(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      maxLines: maxLines,
    );
  }

  Widget _buildStep1(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.store, color: theme.primaryColor, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Bookshop Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Tell us about your bookshop',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            _buildStepText('Bookshop Name'),
            _buildInput(controller: _nameC, hint: 'e.g. Kingdom Books'),
            const SizedBox(height: 16),
            _buildStepText('Description'),
            _buildInput(controller: _descC, hint: 'Describe your bookshop...', maxLines: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.phone, color: theme.primaryColor, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Contact & Location',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'How can customers reach you?',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            _buildStepText('Contact Info'),
            _buildInput(controller: _contactC, hint: 'Phone or email'),
            const SizedBox(height: 16),
            _buildStepText('Location'),
            _buildInput(controller: _locationC, hint: 'Address or area'),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.eye, color: theme.primaryColor, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Preview',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildPreviewRow('Bookshop', _nameC.text),
            const Divider(height: 20),
            _buildPreviewRow('Description', _descC.text),
            const Divider(height: 20),
            _buildPreviewRow('Contact', _contactC.text),
            const Divider(height: 20),
            _buildPreviewRow('Location', _locationC.text),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '(not set)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: value.isNotEmpty ? Colors.black : Colors.grey.shade400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Back'),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                if (_currentStep == 0) {
                  if (!_canProceedFromStep1) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill in all fields'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else if (_currentStep == 1) {
                  if (!_canProceedFromStep2) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill in all fields'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  _submit();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: theme.colorScheme.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: const Size(double.infinity, 48),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_currentStep == 2 ? 'Submit' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }
}
