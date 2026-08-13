import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/tenant_service.dart';

class FileDisputeScreen extends ConsumerStatefulWidget {
  const FileDisputeScreen({super.key, this.initialType, this.initialRef});

  final String? initialType;
  final String? initialRef;

  @override
  ConsumerState<FileDisputeScreen> createState() => _FileDisputeScreenState();
}

class _FileDisputeScreenState extends ConsumerState<FileDisputeScreen> {
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _referenceController = TextEditingController();
  String _type = 'ride';
  final String _priority = 'medium';
  bool _isSubmitting = false;

  static const _types = [
    ('ride', 'Carpso Ride', LucideIcons.car),
    ('delivery', 'Cargo Delivery', LucideIcons.package),
    ('marketplace', 'Marketplace Order', LucideIcons.shoppingBag),
    ('giving', 'Giving / Tithe', LucideIcons.heartHandshake),
    ('payment', 'Payment / Wallet', LucideIcons.creditCard),
    ('subscription', 'Subscription / Plan', LucideIcons.badgeCheck),
    ('other', 'Other', LucideIcons.helpCircle),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) _type = widget.initialType!;
    if (widget.initialRef != null) _referenceController.text = widget.initialRef!;
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_subjectController.text.isEmpty || _descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in subject and description"), backgroundColor: Colors.amber),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client.from('support_disputes').insert({
        'user_id': user.id,
        'tenant_id': ref.read(currentTenantProvider)?.id,
        'dispute_type': _type,
        'reference_id': _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        'subject': _subjectController.text,
        'description': _descriptionController.text,
        'priority': _priority,
        'status': 'open',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Dispute filed! Our COA team will review it within 48 hours."),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error filing dispute: $e"), backgroundColor: Colors.red),
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
        title: Text(
          "FILE A DISPUTE",
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "What went wrong?",
              style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              "Give us the details and any reference number (e.g. ride, order or payment reference) so we can investigate quickly.",
              style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            Text("DISPUTE TYPE", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _types.map((t) {
                final selected = _type == t.$1;
                return ChoiceChip(
                  selected: selected,
                  avatar: Icon(t.$3, size: 16, color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  label: Text(t.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  selectedColor: theme.primaryColor,
                  backgroundColor: theme.colorScheme.surface,
                  labelStyle: TextStyle(color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface),
                  onSelected: (_) => setState(() => _type = t.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _referenceController,
              decoration: InputDecoration(
                labelText: "Reference ID (optional)",
                hintText: "e.g. COA-TXN-2026-A1B2C3",
                prefixIcon: const Icon(LucideIcons.hash, size: 18),
                filled: true,
                fillColor: theme.colorScheme.surface,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.05)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.primaryColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: "Subject",
                hintText: "e.g. Driver never showed up",
                prefixIcon: const Icon(LucideIcons.messageSquare, size: 18),
                filled: true,
                fillColor: theme.colorScheme.surface,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.05)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.primaryColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: "Description",
                hintText: "Describe what happened, when, and who was involved...",
                alignLabelWithHint: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.05)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.primaryColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.onSurface,
                foregroundColor: theme.colorScheme.surface,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: theme.primaryColor, strokeWidth: 2),
                    )
                  : Text(
                      "SUBMIT DISPUTE",
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13),
                    ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
