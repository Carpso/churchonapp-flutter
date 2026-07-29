import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/sos_alert_service.dart';
import 'package:church_on_app/core/utils/location_permission_helper.dart';

class SosTriggerScreen extends StatefulWidget {
  const SosTriggerScreen({super.key});

  @override
  State<SosTriggerScreen> createState() => _SosTriggerScreenState();
}

class _SosTriggerScreenState extends State<SosTriggerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isTriggering = false;
  bool _isTriggered = false;
  int _holdProgress = 0;
  final int _holdDuration = 3;
  String _contactName = '';
  String _contactPhone = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadEmergencyContact();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadEmergencyContact() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _contactName = prefs.getString('sos_contact_name') ?? '';
      _contactPhone = prefs.getString('sos_contact_phone') ?? '';
    });
  }

  Future<void> _saveEmergencyContact(String name, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sos_contact_name', name);
    await prefs.setString('sos_contact_phone', phone);
    setState(() {
      _contactName = name;
      _contactPhone = phone;
    });
  }

  void _showContactSetup() {
    final nameCtrl = TextEditingController(text: _contactName);
    final phoneCtrl = TextEditingController(text: _contactPhone);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Emergency Contact', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('This contact will be shared with dispatchers when you trigger SOS.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Contact Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(LucideIcons.user),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(LucideIcons.phone),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  _saveEmergencyContact(nameCtrl.text.trim(), phoneCtrl.text.trim());
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onHoldComplete() async {
    if (_isTriggered) return;
    setState(() => _isTriggering = true);

    HapticFeedback.heavyImpact();

    if (mounted) {
      await LocationPermissionHelper.showDisclosureIfNeeded(
        context,
        purpose: 'emergency SOS alerts',
      );
    }

    try {
      final service = SosAlertService(Supabase.instance.client);
      await service.triggerSOS(
        contactName: _contactName.isNotEmpty ? _contactName : 'Not set',
        contactPhone: _contactPhone.isNotEmpty ? _contactPhone : 'Not set',
      );

      setState(() {
        _isTriggered = true;
        _isTriggering = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('SOS Alert sent to church dispatchers and admins.'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      setState(() => _isTriggering = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send SOS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('Emergency SOS', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: _showContactSetup,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isTriggered) ...[
              Icon(LucideIcons.shieldCheck, size: 80, color: Colors.green.shade600),
              const SizedBox(height: 24),
              const Text(
                'SOS Alert Sent',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green),
              ),
              const SizedBox(height: 12),
              Text(
                'Dispatchers and admins have been notified.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              ),
              const SizedBox(height: 30),
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.arrowLeft),
                label: const Text('Go Back'),
              ),
            ] else ...[
              Text(
                'Tap and hold for $_holdDuration seconds\nto trigger emergency alert',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
              const SizedBox(height: 40),
              GestureDetector(
                onLongPressStart: (_) async {
                  if (_isTriggering) return;
                  HapticFeedback.mediumImpact();
                  for (int i = 0; i < _holdDuration * 10; i++) {
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (!mounted) return;
                    setState(() => _holdProgress = i + 1);
                  }
                  await _onHoldComplete();
                },
                onLongPressEnd: (_) {
                  if (!_isTriggered) {
                    setState(() => _holdProgress = 0);
                  }
                },
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isTriggering ? 1.0 : _pulseAnimation.value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: _isTriggering
                            ? [Colors.red.shade900, Colors.red.shade700]
                            : [Colors.red.shade700, Colors.red.shade500],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_isTriggering)
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: CircularProgressIndicator(
                              value: _holdProgress / (_holdDuration * 10),
                              strokeWidth: 6,
                              color: Colors.white,
                              backgroundColor: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                        const Icon(LucideIcons.siren, size: 60, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              if (_contactName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.user, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text('$_contactName · $_contactPhone', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _showContactSetup,
                        child: Icon(LucideIcons.pencil, size: 14, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              else
                TextButton.icon(
                  onPressed: _showContactSetup,
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: const Text('Add Emergency Contact'),
                ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Your location will be shared with church admins and dispatchers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
