import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
class KycApplication {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final String? tenantId;
  final String status;
  final DateTime submittedAt;
  final List<Map<String, dynamic>> documents;

  KycApplication({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.tenantId,
    required this.status,
    required this.submittedAt,
    required this.documents,
  });
}

final pendingKycProvider = FutureProvider<List<KycApplication>>((ref) async {
  final client = Supabase.instance.client;
  final currentUser = ref.watch(profileProvider).value;

  final query = client
      .from('profiles')
      .select('id, full_name, avatar_url, tenant_id, kyc_status, created_at')
      .eq('kyc_status', 'pending');

  if (currentUser != null && !currentUser.isSuperadmin && currentUser.role != 'coa_employee' && currentUser.tenantId != null) {
    query.eq('tenant_id', currentUser.tenantId!);
  }

  final profiles = await query as List;

  final apps = <KycApplication>[];
  for (final p in profiles) {
    final docs = await client
        .from('kyc_documents')
        .select('id, document_type, url, status')
        .eq('user_id', p['id'])
        .order('created_at', ascending: false) as List;

    apps.add(KycApplication(
      userId: p['id']?.toString() ?? '',
      userName: p['full_name']?.toString() ?? 'Unknown',
      avatarUrl: p['avatar_url']?.toString(),
      tenantId: p['tenant_id']?.toString(),
      status: p['kyc_status']?.toString() ?? 'pending',
      submittedAt: DateTime.parse(p['created_at']?.toString() ?? DateTime.now().toIso8601String()),
      documents: docs.map((d) => Map<String, dynamic>.from(d as Map)).toList(),
    ));
  }
  return apps;
});

class KycReviewScreen extends ConsumerStatefulWidget {
  const KycReviewScreen({super.key});

  @override
  ConsumerState<KycReviewScreen> createState() => _KycReviewScreenState();
}

class _KycReviewScreenState extends ConsumerState<KycReviewScreen> {
  bool _isProcessing = false;
  String? _processingUserId;

  Future<void> _approve(String userId) async {
    setState(() { _isProcessing = true; _processingUserId = userId; });
    try {
      final client = Supabase.instance.client;
      await client.from('profiles').update({
        'kyc_status': 'verified',
        'is_verified': true,
        'verified_at': DateTime.now().toIso8601String(),
        'verified_by': client.auth.currentUser?.id,
      }).eq('id', userId);

      await client.from('kyc_documents').update({
        'status': 'approved',
        'reviewed_by': client.auth.currentUser?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', userId);

      // Notify the member
      try {
        await client.functions.invoke('push-notifications', body: {
          'userId': userId,
          'title': 'ID Verification Approved',
          'body': 'Your identity has been verified. You now have full access to all features.',
          'data': {
            'type': 'kyc_approved',
            'channel_id': 'coa_announcements',
          },
        });
      } catch (e) {
        debugPrint('[KycReview] Failed to notify user: $e');
      }

      ref.invalidate(pendingKycProvider);
      if (mounted) PremiumToast.showSuccess(context, 'Member verified successfully!', title: 'Approved');
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Failed to approve: $e');
    } finally {
      if (mounted) setState(() { _isProcessing = false; _processingUserId = null; });
    }
  }

  Future<void> _reject(String userId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Rejection Reason'),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Why was this application rejected?',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('REJECT', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    if (reason == null) return;

    setState(() { _isProcessing = true; _processingUserId = userId; });
    try {
      final client = Supabase.instance.client;
      await client.from('profiles').update({
        'kyc_status': 'rejected',
        'is_verified': false,
      }).eq('id', userId);

      await client.from('kyc_documents').update({
        'status': 'rejected',
        'review_notes': reason,
        'reviewed_by': client.auth.currentUser?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', userId);

      // Notify the member
      try {
        await client.functions.invoke('push-notifications', body: {
          'userId': userId,
          'title': 'ID Verification Rejected',
          'body': 'Your ID verification was not approved. Reason: $reason. Please resubmit.',
          'data': {
            'type': 'kyc_rejected',
            'channel_id': 'coa_announcements',
          },
        });
      } catch (e) {
        debugPrint('[KycReview] Failed to notify user: $e');
      }

      ref.invalidate(pendingKycProvider);
      if (mounted) PremiumToast.showSuccess(context, 'Verification rejected', title: 'Rejected');
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Failed to reject: $e');
    } finally {
      if (mounted) setState(() { _isProcessing = false; _processingUserId = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kycAsync = ref.watch(pendingKycProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('ID Verification Review', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: kycAsync.when(
        data: (apps) {
          if (apps.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.shieldCheck, color: Colors.greenAccent, size: 64),
                  SizedBox(height: 20),
                  Text('All Clear!', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('No pending verification requests.', style: TextStyle(color: Colors.white54, fontSize: 14)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: apps.length,
            itemBuilder: (context, i) => _buildCard(apps[i]),
          );
        },
        loading: () => _buildKycShimmer(),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      ),
    );
  }

  Widget _buildKycShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[800]!,
      highlightColor: Colors.grey[600]!,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: List.generate(4, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          )),
        ),
      ),
    );
  }

  Widget _buildCard(KycApplication app) {
    final isProcessing = _isProcessing && _processingUserId == app.userId;
    final docsStr = app.documents.map((d) => d['document_type']?.toString() ?? '').join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: app.avatarUrl != null
                    ? CachedNetworkImageProvider(app.avatarUrl!)
                    : null,
                child: app.avatarUrl == null
                    ? const Icon(LucideIcons.user, color: Colors.white38)
                    : null,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('PENDING', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text('${app.documents.length} document(s)', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (docsStr.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.fileText, color: Colors.white38, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      docsStr.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isProcessing ? null : () => _reject(app.userId),
                  icon: isProcessing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.xCircle, size: 16),
                  label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isProcessing ? null : () => _approve(app.userId),
                  icon: isProcessing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.checkCircle, size: 16, color: Colors.white),
                  label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
