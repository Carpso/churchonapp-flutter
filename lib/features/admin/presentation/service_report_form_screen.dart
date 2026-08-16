import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

class ServiceReportFormScreen extends ConsumerStatefulWidget {
  const ServiceReportFormScreen({super.key});

  @override
  ConsumerState<ServiceReportFormScreen> createState() =>
      _ServiceReportFormScreenState();
}

class _ServiceReportFormScreenState
    extends ConsumerState<ServiceReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  DateTime _serviceDate = DateTime.now();
  String _serviceType = 'sunday';
  int _attendance = 0;
  int _newMembers = 0;
  int _salvations = 0;
  int _baptisms = 0;
  double _offeringAmount = 0;
  double _titheAmount = 0;
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _serviceTypes = [
    {'value': 'sunday', 'label': 'Sunday Service', 'icon': LucideIcons.sun},
    {
      'value': 'wednesday',
      'label': 'Midweek Service',
      'icon': LucideIcons.calendar,
    },
    {
      'value': 'friday',
      'label': 'Friday Service',
      'icon': LucideIcons.moon,
    },
    {
      'value': 'prayer',
      'label': 'Prayer Meeting',
      'icon': LucideIcons.heart,
    },
    {
      'value': 'special',
      'label': 'Special Service',
      'icon': LucideIcons.star,
    },
    {
      'value': 'outreach',
      'label': 'Outreach / Crusade',
      'icon': LucideIcons.megaphone,
    },
  ];

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _serviceDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Theme.of(context).primaryColor,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _serviceDate = picked);
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) {
      PremiumToast.showError(context, 'No church selected');
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      PremiumToast.showError(context, 'Please login first');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await Supabase.instance.client.from('service_reports').insert({
        'tenant_id': tenant.id,
        'church_id': tenant.id,
        'service_date': _serviceDate.toIso8601String().split('T')[0],
        'service_type': _serviceType,
        'attendance': _attendance,
        'new_members': _newMembers,
        'salvations': _salvations,
        'baptisms': _baptisms,
        'offering_amount': _offeringAmount,
        'tithe_amount': _titheAmount,
        'notes': _notesController.text.trim(),
        'created_by': user.id,
      });

      if (mounted) {
        PremiumToast.showSuccess(
          context,
          'Service report submitted successfully!',
          title: 'Report Saved',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        PremiumToast.showError(
          context,
          'Failed to submit report: ${e.toString().replaceAll("Exception: ", "")}',
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tenant = ref.watch(currentTenantProvider);

    final hasReportData = _attendance > 0 ||
        _salvations > 0 ||
        _baptisms > 0 ||
        _offeringAmount > 0 ||
        _titheAmount > 0 ||
        _notesController.text.trim().isNotEmpty ||
        _isSubmitting;

    return PopScope(
      canPop: !hasReportData,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Discard Service Report?"),
            content: const Text(
              "You have entered service statistics or financial records. Leaving now will erase your unsubmitted data.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("CONTINUE EDITING"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text("DISCARD REPORT"),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Service Report',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (tenant != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  tenant.name.length > 15
                      ? '${tenant.name.substring(0, 15)}...'
                      : tenant.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Date & Type ──────────────────────────────
            _buildSectionHeader('Service Details'),
            const SizedBox(height: 12),
            _buildDatePicker(theme),
            const SizedBox(height: 16),
            _buildServiceTypeSelector(theme),

            const SizedBox(height: 30),

            // ── Attendance ───────────────────────────────
            _buildSectionHeader('Attendance'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildNumberField(
                    label: 'Total Attendance',
                    icon: LucideIcons.users,
                    value: _attendance,
                    onChanged: (v) => setState(() => _attendance = v),
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNumberField(
                    label: 'New Members',
                    icon: LucideIcons.userPlus,
                    value: _newMembers,
                    onChanged: (v) => setState(() => _newMembers = v),
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildNumberField(
                    label: 'Salvations',
                    icon: LucideIcons.heart,
                    value: _salvations,
                    onChanged: (v) => setState(() => _salvations = v),
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNumberField(
                    label: 'Baptisms',
                    icon: LucideIcons.droplet,
                    value: _baptisms,
                    onChanged: (v) => setState(() => _baptisms = v),
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // ── Financial ────────────────────────────────
            _buildSectionHeader('Financial Summary'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildCurrencyField(
                    label: 'Offering (K)',
                    icon: LucideIcons.banknote,
                    value: _offeringAmount,
                    onChanged: (v) => setState(() => _offeringAmount = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCurrencyField(
                    label: 'Tithe (K)',
                    icon: LucideIcons.wallet,
                    value: _titheAmount,
                    onChanged: (v) => setState(() => _titheAmount = v),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // ── Notes ────────────────────────────────────
            _buildSectionHeader('Notes & Testimony'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                ),
              ),
              child: TextFormField(
                controller: _notesController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'Key highlights, testimonies, prayer requests...',
                  hintStyle: TextStyle(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // ── Submit ───────────────────────────────────
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'SUBMIT REPORT',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1,
                      ),
                    ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildDatePicker(ThemeData theme) {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.calendar, color: theme.primaryColor, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Service Date',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_serviceDate),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(
              LucideIcons.chevronDown,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceTypeSelector(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _serviceTypes.map((type) {
        final isSelected = _serviceType == type['value'];
        return GestureDetector(
          onTap: () => setState(() => _serviceType = type['value']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.primaryColor.withValues(alpha: 0.15)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? theme.primaryColor
                    : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  type['icon'] as IconData,
                  size: 14,
                  color: isSelected
                      ? theme.primaryColor
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  type['label'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? theme.primaryColor
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNumberField({
    required String label,
    required IconData icon,
    required int value,
    required ValueChanged<int> onChanged,
    Color color = const Color(0xFFFFDA03),
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStepperButton(
                icon: LucideIcons.minus,
                onTap: () {
                  if (value > 0) onChanged(value - 1);
                },
                theme: theme,
              ),
              const SizedBox(width: 16),
              Text(
                '$value',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 16),
              _buildStepperButton(
                icon: LucideIcons.plus,
                onTap: () => onChanged(value + 1),
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: theme.colorScheme.onSurface),
      ),
    );
  }

  Widget _buildCurrencyField({
    required String label,
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    final controller = TextEditingController(
      text: value > 0 ? value.toStringAsFixed(2) : '',
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
            decoration: InputDecoration(
              prefixText: 'K ',
              prefixStyle: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              hintText: '0.00',
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (text) {
              final parsed = double.tryParse(text) ?? 0;
              onChanged(parsed);
            },
          ),
        ],
      ),
    );
  }
}
