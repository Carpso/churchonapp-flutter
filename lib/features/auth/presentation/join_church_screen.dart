import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/code_generator_service.dart';
import '../../../core/services/tenant_service.dart';

class JoinChurchScreen extends ConsumerStatefulWidget {
  final String? churchId;
  final String? churchSlug;
  final String? inviteCode;
  final String? referralCode;

  const JoinChurchScreen({super.key, this.churchId, this.churchSlug, this.inviteCode, this.referralCode});

  @override
  ConsumerState<JoinChurchScreen> createState() => _JoinChurchScreenState();
}

class _JoinChurchScreenState extends ConsumerState<JoinChurchScreen> {
  bool _joining = false;
  String? _error;
  Map<String, dynamic>? _foundTenant;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Handle invite code from deep link (?code=) or referral (?ref=)
    final code = widget.inviteCode ?? widget.referralCode;
    if (code != null && code.isNotEmpty) {
      _lookupCode(code);
    }
  }

  Future<void> _lookupCode(String code) async {
    setState(() { _joining = true; _error = null; _foundTenant = null; });
    try {
      final codeGen = CodeGeneratorService(Supabase.instance.client);
      final record = await codeGen.lookupCode(code);
      if (!mounted) return;
      if (record == null) {
        setState(() { _error = "Invalid invite code. Please check and try again."; _joining = false; });
        return;
      }
      final meta = record['metadata'] as Map<String, dynamic>?;
      final tenantId = meta?['tenant_id'] as String?;
      if (tenantId == null) {
        setState(() { _error = "This invite code is not linked to any church."; _joining = false; });
        return;
      }
      final tenantRes = await Supabase.instance.client
          .from('tenants')
          .select('id, name, type, country')
          .eq('id', tenantId)
          .maybeSingle();
      if (!mounted) return;
      if (tenantRes == null) {
        setState(() { _error = "Church not found. The invite may have expired."; _joining = false; });
        return;
      }
      setState(() { _foundTenant = tenantRes; _joining = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _error = "Error looking up invite: $e"; _joining = false; });
      }
    }
  }

  Future<void> _joinTenant() async {
    if (_foundTenant == null) return;
    setState(() => _joining = true);
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        context.go('/signup');
        return;
      }
      final tenantId = _foundTenant!['id'] as String;
      final tenant = Tenant.fromMap(_foundTenant!);
      await ref.read(currentTenantProvider.notifier).setTenant(tenant);
      await client.from('profiles').update({'tenant_id': tenantId}).eq('id', user.id);
      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Joined ${_foundTenant!['name']}!"), backgroundColor: Colors.green),
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = "Failed to join: $e"; _joining = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    if (user == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text("Join Church")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.church, size: 64, color: Colors.amber),
                const SizedBox(height: 20),
                const Text("Join a Church", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text("Sign in or create an account to join this church.", textAlign: TextAlign.center),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => context.go('/signup'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(200, 50)),
                  child: const Text("Sign Up / Login"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final hasCodeParam = (widget.inviteCode != null && widget.inviteCode!.isNotEmpty) ||
        (widget.referralCode != null && widget.referralCode!.isNotEmpty);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Join Church")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (_foundTenant != null) ...[
              const Icon(LucideIcons.checkCircle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text("Join ${_foundTenant!['name']}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_foundTenant!['country'] ?? '', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _joining ? null : _joinTenant,
                  icon: _joining
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.userPlus),
                  label: Text(_joining ? "Joining..." : "Join This Church"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ] else if (_joining) ...[
              const SizedBox(height: 80),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text("Looking up invite..."),
            ] else ...[
              const Icon(LucideIcons.search, size: 64, color: Colors.amber),
              const SizedBox(height: 20),
              const Text("Enter Invite Code", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text("Paste the invite code your pastor shared with you.", textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                decoration: InputDecoration(
                  hintText: "e.g. COA-ZM_CH_0001",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(LucideIcons.key),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final code = _codeController.text.trim();
                    if (code.isEmpty) return;
                    _lookupCode(code);
                  },
                  icon: const Icon(LucideIcons.arrowRight),
                  label: const Text("Look Up"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ],
            if (hasCodeParam && _error != null && _foundTenant == null) ...[
              const SizedBox(height: 30),
              TextButton(
                onPressed: () => context.go('/select-church'),
                child: const Text("Browse churches instead"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
