import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/two_factor_service.dart';
import 'package:church_on_app/core/widgets/qr_code_with_logo.dart';

class TwoFactorSetupScreen extends ConsumerStatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  ConsumerState<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends ConsumerState<TwoFactorSetupScreen> {
  String? _factorId;
  String? _qrData;
  String? _manualSecret;
  String _verificationCode = '';
  bool _isVerified = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init2fa();
  }

  Future<void> _init2fa() async {
    final service = ref.read(twoFactorServiceProvider);
    final enabled = await service.is2faEnabled();

    if (enabled) {
      setState(() {
        _isVerified = true;
        _isLoading = false;
      });
    } else {
      // Enroll server-side — the secret never touches the client DB.
      final enrollResponse = await service.enroll();
      setState(() {
        _factorId = enrollResponse.id;
        _qrData = enrollResponse.totp?.qrCode;
        _manualSecret = enrollResponse.totp?.secret;
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyAndEnable() async {
    final code = _verificationCode.trim();
    if (code.length != 6 || _factorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid 6-digit code"), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      // Server-side verification: challenge + verify in one call.
      await ref
          .read(twoFactorServiceProvider)
          .verifyAndActivate(factorId: _factorId!, code: code);
      setState(() => _isVerified = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("2FA enabled successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid code. Try again."), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _disable2fa() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Disable 2FA?"),
        content: const Text("This will make your account less secure."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Disable", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(twoFactorServiceProvider).disable2fa();
      // Re-enroll a fresh factor for the setup flow.
      final enrollResponse =
          await ref.read(twoFactorServiceProvider).enroll();
      setState(() {
        _isVerified = false;
        _factorId = enrollResponse.id;
        _qrData = enrollResponse.totp?.qrCode;
        _manualSecret = enrollResponse.totp?.secret;
        _verificationCode = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text("Two-Factor Auth", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isVerified ? LucideIcons.shieldCheck : LucideIcons.shield,
                color: _isVerified ? Colors.green : Colors.amber,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isVerified ? "PROTECTED" : "SETUP REQUIRED",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.onSurface,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isVerified
                  ? "Your account is secured with two-factor authentication."
                  : "Scan the QR code with Google Authenticator or Authy, then enter the 6-digit code below.",
              textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 13),
            ),
            const SizedBox(height: 40),
            if (!_isVerified) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrCodeWithLogo(
                  data: _qrData ?? '',
                  size: 200,
                  logoSize: 40,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Or enter this key manually:",
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  _manualSecret ?? '',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 30),
              TextField(
                onChanged: (val) => _verificationCode = val,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                decoration: InputDecoration(
                  hintText: "000000",
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 24, letterSpacing: 8),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _verifyAndEnable,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  "VERIFY & ENABLE",
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Column(
                  children: [
                    Icon(LucideIcons.checkCircle, color: Colors.green, size: 40),
                    SizedBox(height: 12),
                    Text(
                      "Two-factor authentication is active",
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              OutlinedButton.icon(
                onPressed: _disable2fa,
                icon: const Icon(LucideIcons.shieldOff),
                label: const Text("DISABLE 2FA"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}