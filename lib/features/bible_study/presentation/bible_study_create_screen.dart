import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/bible_study/data/bible_study_service.dart';
import 'package:church_on_app/features/bible_study/data/bible_study_providers.dart';

class BibleStudyCreateScreen extends ConsumerStatefulWidget {
  final BibleStudy? study;

  const BibleStudyCreateScreen({super.key, this.study});

  @override
  ConsumerState<BibleStudyCreateScreen> createState() => _BibleStudyCreateScreenState();
}

class _BibleStudyCreateScreenState extends ConsumerState<BibleStudyCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _leaderController;
  late TextEditingController _locationController;
  late TextEditingController _materialsController;
  late TextEditingController _maxAttendeesController;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _isSaving = false;

  bool get _isEditing => widget.study != null;

  @override
  void initState() {
    super.initState();
    final study = widget.study;
    _titleController = TextEditingController(text: study?.title ?? '');
    _descriptionController = TextEditingController(text: study?.description ?? '');
    _leaderController = TextEditingController(text: study?.leader ?? '');
    _locationController = TextEditingController(text: study?.location ?? '');
    _materialsController = TextEditingController(text: study?.materialsUrl ?? '');
    _maxAttendeesController = TextEditingController(
      text: study != null && study.maxAttendees > 0 ? study.maxAttendees.toString() : '',
    );
    _selectedDate = study?.date ?? DateTime.now().add(const Duration(days: 7));
    _selectedTime = _parseTime(study?.time);
  }

  TimeOfDay _parseTime(String? time) {
    if (time == null || time.isEmpty) return const TimeOfDay(hour: 9, minute: 0);
    final parts = time.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]) ?? 9;
      final minute = int.tryParse(parts[1]) ?? 0;
      return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
    }
    return const TimeOfDay(hour: 9, minute: 0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _leaderController.dispose();
    _locationController.dispose();
    _materialsController.dispose();
    _maxAttendeesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final tenantId = tenant?.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Bible Study' : 'New Bible Study'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: tenantId == null
          ? const Center(child: Text('No church selected'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(
                      controller: _titleController,
                      label: 'Title',
                      hint: 'e.g., Book of Romans Study',
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => v?.trim().isEmpty == true ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _descriptionController,
                      label: 'Description',
                      hint: 'Describe what this study will cover',
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),
                    _buildDatePicker(),
                    const SizedBox(height: 12),
                    _buildTimePicker(),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _leaderController,
                      label: 'Leader',
                      hint: 'Name of the study leader',
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => v?.trim().isEmpty == true ? 'Leader is required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _locationController,
                      label: 'Location',
                      hint: 'e.g., Main Hall, Room 3',
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => v?.trim().isEmpty == true ? 'Location is required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _materialsController,
                      label: 'Materials URL (optional)',
                      hint: 'Link to study materials',
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _maxAttendeesController,
                      label: 'Max Attendees (optional)',
                      hint: 'Leave empty for unlimited',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          disabledBackgroundColor: Colors.indigo.shade200,
                        ),
                        onPressed: _isSaving ? null : () => _save(tenantId),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_isEditing ? 'Update Study' : 'Create Study'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.indigo, width: 2),
        ),
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  Widget _buildDatePicker() {
    final dateFormat = DateFormat('MMM d, yyyy');
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
            const Icon(Icons.calendar_today, color: Colors.indigo, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(dateFormat.format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker() {
    final timeFormat = DateFormat.jm();
    final timeDateTime = DateTime(2024, 1, 1, _selectedTime.hour, _selectedTime.minute);
    return GestureDetector(
      onTap: _pickTime,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, color: Colors.indigo, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Time', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(timeFormat.format(timeDateTime), style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _save(String tenantId) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final service = ref.read(bibleStudyServiceProvider);
      final timeStr = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
      final maxAttendees = int.tryParse(_maxAttendeesController.text.trim()) ?? 0;

      if (_isEditing) {
        await service.updateStudy(
          id: widget.study!.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          date: _selectedDate,
          time: timeStr,
          leader: _leaderController.text.trim(),
          location: _locationController.text.trim(),
          materialsUrl: _materialsController.text.trim().isEmpty ? null : _materialsController.text.trim(),
          maxAttendees: maxAttendees,
        );
      } else {
        await service.createStudy(
          tenantId: tenantId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          date: _selectedDate,
          time: timeStr,
          leader: _leaderController.text.trim(),
          location: _locationController.text.trim(),
          materialsUrl: _materialsController.text.trim().isEmpty ? null : _materialsController.text.trim(),
          maxAttendees: maxAttendees,
        );
      }

      ref.invalidate(studiesProvider(tenantId));
      ref.invalidate(upcomingStudiesProvider(tenantId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEditing ? 'Study updated!' : 'Study created!'),
          backgroundColor: Colors.green,
        ));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
