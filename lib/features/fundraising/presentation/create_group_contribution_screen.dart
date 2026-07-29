import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import '../data/fundraising_providers.dart';

class CreateGroupContributionScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const CreateGroupContributionScreen({super.key, required this.tenantId});

  @override
  ConsumerState<CreateGroupContributionScreen> createState() => _CreateGroupContributionScreenState();
}

class _CreateGroupContributionScreenState extends ConsumerState<CreateGroupContributionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _minCtrl = TextEditingController(text: "1");
  final _maxCtrl = TextEditingController();
  String _frequency = "one_time";
  DateTime? _endDate;
  bool _isSubmitting = false;

  final List<String> _frequencies = ["one_time", "weekly", "monthly"];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _targetCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final authUser = ref.read(authProvider).user;
      if (authUser == null) throw Exception("Not authenticated");

      final service = ref.read(groupContributionServiceProvider);
      await service.createGroup(
        tenantId: widget.tenantId,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        targetAmount: double.tryParse(_targetCtrl.text.trim()) ?? 0.0,
        frequency: _frequency,
        minAmount: double.tryParse(_minCtrl.text.trim()) ?? 1,
        maxAmount: double.tryParse(_maxCtrl.text.trim()),
        endDate: _endDate,
        createdBy: authUser.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Group created successfully!"), backgroundColor: Colors.green),
        );
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) Navigator.pop(context, true);
        });
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Create Group Contribution", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildField("Group Title", _titleCtrl, "e.g. Building Fund Drive", LucideIcons.tag, validator: (v) {
                if (v == null || v.trim().isEmpty) return "Title is required";
                return null;
              }),
              const SizedBox(height: 16),
              _buildField("Description (Optional)", _descCtrl, "What is this group for?", LucideIcons.fileText, maxLines: 3),
              const SizedBox(height: 16),
              _buildField("Target Amount (K)", _targetCtrl, "e.g. 5000", LucideIcons.trendingUp, keyboardType: TextInputType.number, validator: (v) {
                if (v == null || v.trim().isEmpty) return "Target is required";
                if (double.tryParse(v.trim()) == null || (double.tryParse(v.trim()) ?? 0) <= 0) return "Enter a valid amount";
                return null;
              }),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildField("Min Amount (K)", _minCtrl, "1", LucideIcons.minimize2, keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildField("Max Amount (K)", _maxCtrl, "Optional", LucideIcons.maximize2, keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 20),
              const Text("Frequency", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              Row(
                children: _frequencies.map((f) {
                  final selected = _frequency == f;
                  final labels = {"one_time": "One-Time", "weekly": "Weekly", "monthly": "Monthly"};
                  final icons = {"one_time": LucideIcons.target, "weekly": LucideIcons.calendar, "monthly": LucideIcons.calendarRange};
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _frequency = f),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected ? theme.colorScheme.secondary : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selected ? theme.colorScheme.secondary : Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Icon(icons[f]!, size: 18, color: selected ? Colors.white : Colors.grey),
                            const SizedBox(height: 4),
                            Text(labels[f]!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: selected ? Colors.white : Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(LucideIcons.calendar, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text("End Date", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey.shade700)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) setState(() => _endDate = picked);
                    },
                    icon: Icon(LucideIcons.calendarPlus, size: 16, color: theme.colorScheme.secondary),
                    label: Text(
                      _endDate != null ? "${_endDate!.day}/${_endDate!.month}/${_endDate!.year}" : "Set end date (optional)",
                      style: TextStyle(color: _endDate != null ? theme.colorScheme.secondary : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("CREATE GROUP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1, TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
