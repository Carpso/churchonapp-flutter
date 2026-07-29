import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/whatsapp_service.dart';

class WhatsAppConfigScreen extends ConsumerStatefulWidget {
  const WhatsAppConfigScreen({super.key});

  @override
  ConsumerState<WhatsAppConfigScreen> createState() => _WhatsAppConfigScreenState();
}

class _WhatsAppConfigScreenState extends ConsumerState<WhatsAppConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEnabled = false;
  bool _isLoading = true;
  bool _isSaving = false;

  final _phoneNumberIdController = TextEditingController();
  final _accessTokenController = TextEditingController();
  final _businessAccountIdController = TextEditingController();
  final _verifyTokenController = TextEditingController();
  final _webhookUrlController = TextEditingController();
  final _appIdController = TextEditingController();
  final _whatsappNumberController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final service = ref.read(whatsappServiceProvider);
    final config = await service.getConfig();
    if (config != null && mounted) {
      setState(() {
        _isEnabled = config['is_enabled'] ?? false;
        _phoneNumberIdController.text = config['phone_number_id'] ?? '';
        _accessTokenController.text = config['access_token'] ?? '';
        _businessAccountIdController.text = config['business_account_id'] ?? '';
        _verifyTokenController.text = config['verify_token'] ?? '';
        _webhookUrlController.text = config['webhook_url'] ?? '';
        _appIdController.text = config['app_id'] ?? '';
        _whatsappNumberController.text = config['whatsapp_number'] ?? '';
        _descriptionController.text = config['description'] ?? '';
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final service = ref.read(whatsappServiceProvider);
      await service.updateConfig(
        isEnabled: _isEnabled,
        phoneNumberId: _phoneNumberIdController.text.trim(),
        accessToken: _accessTokenController.text.trim(),
        businessAccountId: _businessAccountIdController.text.trim(),
        verifyToken: _verifyTokenController.text.trim(),
        webhookUrl: _webhookUrlController.text.trim(),
        appId: _appIdController.text.trim(),
        whatsappNumber: _whatsappNumberController.text.trim(),
        description: _descriptionController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp configuration saved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('WhatsApp Configuration', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _isEnabled ? const Color(0xFFDCF8C6) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.messageCircle,
                            color: _isEnabled ? const Color(0xFF075E54) : Colors.grey,
                            size: 30,
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isEnabled ? 'WhatsApp Integration Active' : 'WhatsApp Integration Disabled',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _isEnabled ? const Color(0xFF075E54) : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Configure WhatsApp Business API credentials',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isEnabled,
                            onChanged: (v) => setState(() => _isEnabled = v),
                            activeTrackColor: const Color(0xFF075E54),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text('WHATSAPP NUMBER & DESCRIPTION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                    const SizedBox(height: 15),
                    _buildField('WhatsApp Number (e.g. +260971234567)', _whatsappNumberController, LucideIcons.phone),
                    _buildField('Description (shown to users)', _descriptionController, LucideIcons.alignLeft),
                    const SizedBox(height: 30),
                    const Text('API CREDENTIALS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                    const SizedBox(height: 15),
                    _buildField('Phone Number ID', _phoneNumberIdController, LucideIcons.phone),
                    _buildField('Access Token', _accessTokenController, LucideIcons.key, obscure: true),
                    _buildField('Business Account ID', _businessAccountIdController, LucideIcons.building),
                    _buildField('Verify Token', _verifyTokenController, LucideIcons.shield),
                    _buildField('Webhook URL', _webhookUrlController, LucideIcons.link),
                    _buildField('App ID', _appIdController, LucideIcons.appWindow),
                    const SizedBox(height: 30),
                    const Text('WEBHOOK SETUP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Set your WhatsApp webhook URL to:', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                          const SizedBox(height: 5),
                          Text(
                            'https://daboihiudmglwhdfvsku.supabase.co/functions/v1/whatsapp-webhook',
                            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blue.shade900),
                          ),
                          const SizedBox(height: 10),
                          Text('Verify Token: ${_verifyTokenController.text.isEmpty ? '(set above)' : _verifyTokenController.text}',
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF075E54),
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('SAVE CONFIGURATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: TextFormField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            icon: Icon(icon, color: const Color(0xFF075E54), size: 18),
            labelText: label,
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
