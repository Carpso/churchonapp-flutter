import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

class PollData {
  final String question;
  final List<String> options;
  final String duration;
  final DateTime createdAt;

  PollData({
    required this.question,
    required this.options,
    required this.duration,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class PollStore extends Notifier<List<PollData>> {
  @override
  List<PollData> build() => [];

  void addPoll(PollData poll) {
    state = [...state, poll];
  }
}

final pollStoreProvider = NotifierProvider<PollStore, List<PollData>>(PollStore.new);

class PollCreatorScreen extends ConsumerStatefulWidget {
  const PollCreatorScreen({super.key});

  @override
  ConsumerState<PollCreatorScreen> createState() => _PollCreatorScreenState();
}

class _PollCreatorScreenState extends ConsumerState<PollCreatorScreen> {
  final _questionC = TextEditingController();
  final _optionControllers = <TextEditingController>[TextEditingController(), TextEditingController()];
  String _selectedDuration = '24h';
  bool _isSubmitting = false;

  final _durations = [
    ('24h', '24 Hours'),
    ('48h', '48 Hours'),
    ('7d', '7 Days'),
  ];

  @override
  void dispose() {
    _questionC.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (_questionC.text.trim().isEmpty) {
      _showError('Please enter a question');
      return;
    }
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (options.length < 2) {
      _showError('Please provide at least 2 options');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // Simulate network delay
      await Future.delayed(const Duration(seconds: 1));
      ref.read(pollStoreProvider.notifier).addPoll(
        PollData(
          question: _questionC.text.trim(),
          options: options,
          duration: _selectedDuration,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Poll created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showError('Error creating poll: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('Create Poll'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Question', style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  )),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _questionC,
                    decoration: InputDecoration(
                      hintText: 'Ask something...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFFFFAEB),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  Text('Options', style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  )),
                  const SizedBox(height: 8),
                  ...List.generate(_optionControllers.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _optionControllers[index],
                              decoration: InputDecoration(
                                hintText: 'Option ${index + 1}',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFFFFAEB),
                              ),
                            ),
                          ),
                          if (_optionControllers.length > 2)
                            IconButton(
                              icon: Icon(LucideIcons.x, color: Colors.red.shade300, size: 20),
                              onPressed: () => _removeOption(index),
                            ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: const Text('Add Option'),
                  ),
                  const SizedBox(height: 24),
                  Text('Duration', style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  )),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: _durations.map((d) {
                      final isSelected = _selectedDuration == d.$1;
                      return ChoiceChip(
                        label: Text(d.$2),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _selectedDuration = d.$1),
                        selectedColor: theme.primaryColor.withValues(alpha: 0.2),
                        backgroundColor: Colors.grey.shade100,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.send),
                label: Text(_isSubmitting ? 'Creating...' : 'Create Poll'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.secondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
