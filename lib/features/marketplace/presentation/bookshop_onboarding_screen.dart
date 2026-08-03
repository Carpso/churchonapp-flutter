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
  final _formKey1 = GlobalKey<FormState>();
  final _formKey2 = GlobalKey<FormState>();
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

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Bookshop name is required';
    if (v.trim().length < 2) return 'Min 2 characters';
    return null;
  }

  String? _validateDesc(String? v) {
    if (v == null || v.trim().isEmpty) return 'Description is required';
    if (v.trim().length < 5) return 'Min 5 characters';
    return null;
  }

  String? _validateContact(String? v) {
    if (v == null || v.trim().isEmpty) return 'Contact is required';
    final trimmed = v.trim();
    final isEmail = trimmed.contains('@') && trimmed.contains('.');
    final isPhone = RegExp(r'^\d{10,13}$').hasMatch(trimmed.replaceAll(RegExp(r'[\s\-\+]'), ''));
    if (!isEmail && !isPhone) return 'Enter a valid phone number or email';
    return null;
  }

  String? _validateLocation(String? v) {
    if (v == null || v.trim().isEmpty) return 'Location is required';
    if (v.trim().length < 3) return 'Enter a valid location';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception("Not logged in");

      final response = await client.functions.invoke('create-bookshop', body: {
        'name': _nameC.text.trim(),
        'description': _descC.text.trim(),
        'contact': _contactC.text.trim(),
        'location': _locationC.text.trim(),
      });
      final result = response.data as Map<String, dynamic>?;
      if (result == null || result['success'] != true) {
        throw Exception(result?['error'] ?? 'Failed to create bookshop');
      }

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Set Up Bookshop'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.7)],
              ),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.store, color: Colors.white, size: 22),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step ${_currentStep + 1} of 3',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      _currentStep == 0
                          ? 'Bookshop Details'
                          : _currentStep == 1
                              ? 'Contact & Location'
                              : 'Review & Submit',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: List.generate(3, (i) {
                final isActive = i <= _currentStep;
                return Expanded(
                  child: Container(
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: isActive ? theme.primaryColor : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(3),
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

  Widget _buildSectionHeader(IconData icon, String title, String subtitle, ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.primaryColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep1(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Form(
        key: _formKey1,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(LucideIcons.store, 'Bookshop Details', 'Tell us about your bookshop', theme),
              const SizedBox(height: 28),
              const Text('Bookshop Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameC,
                validator: _validateName,
                decoration: InputDecoration(
                  hintText: 'e.g. Faith Books',
                  prefixIcon: const Icon(LucideIcons.store, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 20),
              const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descC,
                validator: _validateDesc,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe your bookshop...',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Icon(LucideIcons.bookOpen, size: 18),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep2(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Form(
        key: _formKey2,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(LucideIcons.phone, 'Contact & Location', 'How can customers reach you?', theme),
              const SizedBox(height: 28),
              const Text('Contact Info', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _contactC,
                validator: _validateContact,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Phone number or email',
                  prefixIcon: const Icon(LucideIcons.phone, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 20),
              const Text('Location', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _locationC,
                validator: _validateLocation,
                decoration: InputDecoration(
                  hintText: 'Address or area',
                  prefixIcon: const Icon(LucideIcons.mapPin, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep3(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(LucideIcons.eye, 'Preview', 'Review your bookshop details', theme),
            const SizedBox(height: 24),
            _buildPreviewRow(LucideIcons.store, 'Bookshop', _nameC.text),
            const Divider(height: 24),
            _buildPreviewRow(LucideIcons.bookOpen, 'Description', _descC.text),
            const Divider(height: 24),
            _buildPreviewRow(LucideIcons.phone, 'Contact', _contactC.text),
            const Divider(height: 24),
            _buildPreviewRow(LucideIcons.mapPin, 'Location', _locationC.text),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value.isNotEmpty ? value : '(not set)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: value.isNotEmpty ? Colors.black : Colors.grey.shade400,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 3,
          ),
        ),
      ],
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
                  if (!_formKey1.currentState!.validate()) return;
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else if (_currentStep == 1) {
                  if (!_formKey2.currentState!.validate()) return;
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
