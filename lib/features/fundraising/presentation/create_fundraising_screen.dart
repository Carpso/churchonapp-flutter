import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_models.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_providers.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/r2_service.dart';

class CreateFundraisingScreen extends ConsumerStatefulWidget {
  const CreateFundraisingScreen({super.key});

  @override
  ConsumerState<CreateFundraisingScreen> createState() => _CreateFundraisingScreenState();
}

class _CreateFundraisingScreenState extends ConsumerState<CreateFundraisingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetController = TextEditingController();
  final _picker = ImagePicker();

  FundraisingCategory _category = FundraisingCategory.missions;
  String _currency = 'ZMW';
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  bool _allowPartnerContributions = false;
  List<String> _selectedPartnerIds = [];
  bool _inviteAllChurches = false;
  File? _selectedImage;
  String? _imageUrl;
  bool _isLoading = false;
  bool _imageUploading = false;

  final List<String> _currencies = ['ZMW', 'USD'];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('New Fundraising Venture'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImagePicker(theme),
              const SizedBox(height: 24),
              _buildSectionTitle('Title'),
              const SizedBox(height: 8),
              _buildTitleField(theme),
              const SizedBox(height: 20),
              _buildSectionTitle('Description'),
              const SizedBox(height: 8),
              _buildDescriptionField(theme),
              const SizedBox(height: 20),
              _buildSectionTitle('Category'),
              const SizedBox(height: 8),
              _buildCategorySelector(theme),
              const SizedBox(height: 20),
              _buildSectionTitle('Target Amount'),
              const SizedBox(height: 8),
              _buildTargetAmountField(theme),
              const SizedBox(height: 20),
              _buildSectionTitle('End Date'),
              const SizedBox(height: 8),
              _buildDatePicker(theme),
              const SizedBox(height: 24),
              _buildPartnerToggle(),
              if (_allowPartnerContributions) ...[
                const SizedBox(height: 12),
                _buildPartnerOptions(theme),
              ],
              const SizedBox(height: 32),
              _buildPreviewCard(theme),
              const SizedBox(height: 32),
              _buildSubmitButton(theme),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildImagePicker(ThemeData theme) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          image: _selectedImage != null
              ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
              : null,
        ),
        child: _selectedImage == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.image, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('Tap to add a cover image', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Optional but recommended', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                ],
              )
            : Stack(
                children: [
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedImage = null),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.x, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                  if (_imageUploading)
                    Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: const Center(child: CircularProgressIndicator(color: Color(0xFFFFB300))),
                    ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.camera, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text('Change', style: TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTitleField(ThemeData theme) {
    return TextFormField(
      controller: _titleController,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: 'e.g. Build a School in Zambia',
        hintStyle: TextStyle(color: Colors.grey.shade400),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Title is required';
        if (v.trim().length < 5) return 'Title must be at least 5 characters';
        return null;
      },
    );
  }

  Widget _buildDescriptionField(ThemeData theme) {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 5,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Tell your story and explain why this matters...',
        hintStyle: TextStyle(color: Colors.grey.shade400),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Description is required';
        if (v.trim().length < 20) return 'Please provide at least 20 characters';
        return null;
      },
    );
  }

  Widget _buildCategorySelector(ThemeData theme) {
    final categories = FundraisingCategory.values;
    final labels = {
      FundraisingCategory.building: 'Building',
      FundraisingCategory.missions: 'Missions',
      FundraisingCategory.youth: 'Youth',
      FundraisingCategory.community: 'Community',
      FundraisingCategory.emergency: 'Emergency',
      FundraisingCategory.other: 'Other',
    };
    final icons = {
      FundraisingCategory.building: LucideIcons.building2,
      FundraisingCategory.missions: LucideIcons.globe,
      FundraisingCategory.youth: LucideIcons.heart,
      FundraisingCategory.community: LucideIcons.users,
      FundraisingCategory.emergency: LucideIcons.alertTriangle,
      FundraisingCategory.other: LucideIcons.hand,
    };
    final colors = {
      FundraisingCategory.building: const Color(0xFF3B82F6),
      FundraisingCategory.missions: const Color(0xFF10B981),
      FundraisingCategory.youth: const Color(0xFFF59E0B),
      FundraisingCategory.community: const Color(0xFF8B5CF6),
      FundraisingCategory.emergency: const Color(0xFFEF4444),
      FundraisingCategory.other: const Color(0xFF6B7280),
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((category) {
        final isSelected = _category == category;
        final color = colors[category]!;
        return GestureDetector(
          onTap: () => setState(() => _category = category),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade200,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icons[category], size: 16, color: isSelected ? color : Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  labels[category]!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? color : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTargetAmountField(ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _currency,
              items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
              onChanged: (v) => setState(() => _currency = v!),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _targetController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final amount = double.tryParse(v.trim());
              if (amount == null || amount <= 0) return 'Enter a valid amount';
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(ThemeData theme) {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.calendar, size: 20, color: Color(0xFFFFB300)),
            const SizedBox(width: 12),
            Text(
              DateFormat('MMM dd, yyyy').format(_endDate),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Text(
              '${_endDate.difference(DateTime.now()).inDays} days from now',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartnerToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.share2, size: 20, color: Color(0xFFFFB300)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Allow partner churches to contribute', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text('Invite other churches to join this venture', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Switch(
            value: _allowPartnerContributions,
            onChanged: (v) => setState(() => _allowPartnerContributions = v),
            activeThumbColor: const Color(0xFFFFB300),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerOptions(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Invite churches', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.colorScheme.secondary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _inviteAllChurches,
            onChanged: (v) => setState(() {
              _inviteAllChurches = v ?? false;
              if (_inviteAllChurches) _selectedPartnerIds = [];
            }),
            title: const Text('All churches', style: TextStyle(fontSize: 14)),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          if (!_inviteAllChurches) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedPartnerIds.isEmpty
                          ? 'Select partner churches...'
                          : '${_selectedPartnerIds.length} church${_selectedPartnerIds.length == 1 ? '' : 'es'} selected',
                      style: TextStyle(color: _selectedPartnerIds.isEmpty ? Colors.grey.shade400 : Colors.black87, fontSize: 14),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.chevronDown, size: 18),
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewCard(ThemeData theme) {
    final title = _titleController.text.isEmpty ? 'Your Venture Title' : _titleController.text;
    final target = double.tryParse(_targetController.text) ?? 0;
    final categoryColors = {
      FundraisingCategory.building: const Color(0xFF3B82F6),
      FundraisingCategory.missions: const Color(0xFF10B981),
      FundraisingCategory.youth: const Color(0xFFF59E0B),
      FundraisingCategory.community: const Color(0xFF8B5CF6),
      FundraisingCategory.emergency: const Color(0xFFEF4444),
      FundraisingCategory.other: const Color(0xFF6B7280),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      categoryColors[_category] ?? const Color(0xFFFFB300),
                      (categoryColors[_category] ?? const Color(0xFFFFB300)).withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Icon(_categoryIcon(_category), size: 40, color: Colors.white.withValues(alpha: 0.3)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.secondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('$_currency 0 raised of $_currency ${target > 0 ? target.toStringAsFixed(0) : '0'}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        const Spacer(),
                        Text('0%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFFFB300))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFB300),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Text('Create Venture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  IconData _categoryIcon(FundraisingCategory category) {
    switch (category) {
      case FundraisingCategory.building: return LucideIcons.building2;
      case FundraisingCategory.missions: return LucideIcons.globe;
      case FundraisingCategory.youth: return LucideIcons.heart;
      case FundraisingCategory.community: return LucideIcons.users;
      case FundraisingCategory.emergency: return LucideIcons.alertTriangle;
      case FundraisingCategory.other: return LucideIcons.hand;
    }
  }

  Future<void> _pickImage() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              const Text('Choose Image Source', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _sourceOption(LucideIcons.camera, 'Camera', ImageSource.camera),
                  _sourceOption(LucideIcons.image, 'Gallery', ImageSource.gallery),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
      if (source == null) return;
      final picked = await _picker.pickImage(source: source, imageQuality: 80);
      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
          _imageUploading = true;
        });
        try {
          final r2 = R2Service(ref.read(supabaseServiceProvider).client);
          final fileName = 'ventures/${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
          final url = await r2.uploadFile(_selectedImage!, fileName);
          if (mounted) {
            setState(() {
              _imageUrl = url;
              _imageUploading = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() => _imageUploading = false);
            PremiumToast.showError(context, 'Failed to upload image');
          }
        }
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Failed to pick image');
    }
  }

  Widget _sourceOption(IconData icon, String label, ImageSource source) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFAEB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 32, color: const Color(0xFFFFB300)),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFFFB300)),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final tenant = ref.read(currentTenantProvider);
      if (tenant?.id == null) {
        if (mounted) PremiumToast.showError(context, 'No church selected');
        return;
      }

      final venture = await ref.read(fundraisingServiceProvider).createVenture(
        tenantId: tenant!.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category.name,
        targetAmount: double.tryParse(_targetController.text.trim()) ?? 0.0,
        currency: _currency,
        imageUrl: _imageUrl,
        endDate: _endDate,
        allowOtherTenants: _allowPartnerContributions,
        allowedTenantIds: _inviteAllChurches ? [] : _selectedPartnerIds,
        createdBy: ref.read(authProvider).user?.id,
      );

      if (mounted) {
        PremiumToast.showSuccess(context, 'Venture created successfully!');
        context.push('/fundraising/$venture');
      }
    } catch (e) {
      if (mounted) {
        PremiumToast.showError(context, 'Failed to create venture: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
