import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import '../data/fundraising_models.dart';
import '../data/fundraising_providers.dart';
import '../../finance/presentation/lipila_payment_gateway.dart';

class GroupContributionDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupContributionDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupContributionDetailScreen> createState() => _GroupContributionDetailScreenState();
}

class _GroupContributionDetailScreenState extends ConsumerState<GroupContributionDetailScreen> {
  String? _myMemberId;
  bool _isJoining = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authUser = ref.watch(authProvider).user;
    final service = ref.read(groupContributionServiceProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Group Contribution", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.share2),
            onPressed: () {
              SharePlus.instance.share(
                ShareParams(text: "Join our group contribution on Church On App!"),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGroupDetailCard(theme),
            const SizedBox(height: 24),
            _buildActionButtons(theme, authUser, service),
            const SizedBox(height: 24),
            _buildMembersSection(theme),
            const SizedBox(height: 24),
            _buildPaymentsSection(theme),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkMembership();
  }

  Future<void> _checkMembership() async {
    final authUser = ref.read(authProvider).user;
    if (authUser == null) return;
    final service = ref.read(groupContributionServiceProvider);
    final member = await service.getMyMembership(widget.groupId, authUser.id);
    if (member != null && mounted) {
      setState(() => _myMemberId = member.id);
    }
  }

  Widget _buildGroupDetailCard(ThemeData theme) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    return groupAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text("Error loading group", style: TextStyle(color: Colors.red))),
      data: (g) {
        if (g == null) return const SizedBox.shrink();
        final progress = g.targetAmount > 0 ? (g.collectedAmount / g.targetAmount) : 0.0;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade200,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("K ${g.collectedAmount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("Goal: K ${g.targetAmount.toStringAsFixed(0)}", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              Text("${(progress * 100).toInt()}% complete", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(ThemeData theme, dynamic authUser, dynamic service) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_myMemberId != null) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _contribute(theme),
                icon: const Icon(LucideIcons.hand, color: Colors.white, size: 20),
                label: const Text("CONTRIBUTE NOW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isJoining ? null : () => _joinGroup(theme),
                icon: _isJoining
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.userPlus, color: Colors.white, size: 20),
                label: Text(
                  _isJoining ? "Joining..." : "JOIN THIS GROUP",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _joinGroup(ThemeData theme) async {
    final authUser = ref.read(authProvider).user;
    if (authUser == null) {
      PremiumToast.showError(context, "Please sign in first");
      return;
    }

    setState(() => _isJoining = true);
    try {
      final service = ref.read(groupContributionServiceProvider);
      final amount = await showDialog<double>(
        context: context,
        builder: (ctx) => _PledgeDialog(),
      );
      if (amount == null || amount <= 0) {
        setState(() => _isJoining = false);
        return;
      }

      final userName = authUser.userMetadata?['full_name'] ?? authUser.email ?? "Member";
      await service.joinGroup(
        groupId: widget.groupId,
        userId: authUser.id,
        userName: userName,
        pledgedAmount: amount,
      );

      await _checkMembership();
      if (mounted) {
        PremiumToast.showSuccess(context, "You've joined the group!");
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, "Failed to join: $e");
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _contribute(ThemeData theme) async {
    if (_myMemberId == null) return;
    final authUser = ref.read(authProvider).user;
    if (authUser == null) return;

    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => _ContributionAmountDialog(),
    );
    if (amount == null || amount <= 0) return;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LipilaPaymentGateway(
        amount: amount,
        description: "Group Contribution",
        category: "giving",
        onComplete: (success, txId) async {
          Navigator.pop(ctx);
          if (success) {
            try {
              final service = ref.read(groupContributionServiceProvider);
              final userName = authUser.userMetadata?['full_name'] ?? authUser.email ?? "Member";
              await service.contribute(
                groupId: widget.groupId,
                memberId: _myMemberId!,
                userName: userName,
                amount: amount,
              );
              if (mounted) PremiumToast.showSuccess(context, "Contribution received!");
            } catch (e) {
              if (mounted) PremiumToast.showError(context, "Error recording contribution: $e");
            }
          }
        },
      ),
    );
  }

  Widget _buildMembersSection(ThemeData theme) {
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.userCheck, size: 18, color: theme.colorScheme.secondary),
            const SizedBox(width: 8),
            Text("Members", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.secondary)),
          ],
        ),
        const SizedBox(height: 12),
        membersAsync.when(
          data: (members) {
            if (members.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text("No members yet", style: TextStyle(color: Colors.grey)));
            return ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: members.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _MemberTile(member: members[i], isMe: members[i].id == _myMemberId),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        error: (e, _) => Text("Error: $e", style: const TextStyle(color: Colors.red)),
      ),
    ],
  );
}

Widget _buildPaymentsSection(ThemeData theme) {
    final paymentsAsync = ref.watch(groupPaymentsProvider(widget.groupId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.receipt, size: 18, color: theme.colorScheme.secondary),
            const SizedBox(width: 8),
            Text("Payment Feed", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.secondary)),
          ],
        ),
        const SizedBox(height: 12),
        paymentsAsync.when(
          data: (payments) {
            if (payments.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text("No payments yet", style: TextStyle(color: Colors.grey)));
            return ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: payments.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _PaymentTile(payment: payments[i]),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text("Error: $e", style: const TextStyle(color: Colors.red)),
        ),
    ],
  );
}
}

class _MemberTile extends StatelessWidget {
  final GroupContributionMember member;
  final bool isMe;

  const _MemberTile({required this.member, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final progress = member.pledgedAmount > 0 ? (member.paidAmount / member.pledgedAmount) : 0.0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isMe ? Colors.amber.shade100 : Colors.grey.shade200,
        child: Text(
          member.userName.isNotEmpty ? member.userName[0].toUpperCase() : "?",
          style: TextStyle(fontWeight: FontWeight.bold, color: isMe ? Colors.brown : Colors.grey.shade700),
        ),
      ),
      title: Row(
        children: [
          Text(member.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          if (isMe)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
              child: Text("You", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.brown.shade700)),
            ),
        ],
      ),
      subtitle: Text("Paid K${member.paidAmount.toStringAsFixed(0)} / K${member.pledgedAmount.toStringAsFixed(0)}", style: const TextStyle(fontSize: 12)),
      trailing: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(value: progress.clamp(0, 1), strokeWidth: 4, backgroundColor: Colors.grey.shade200, color: progress >= 1 ? Colors.green : Colors.amber),
            Text("${(progress * 100).toInt()}%", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: progress >= 1 ? Colors.green : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final GroupContributionPayment payment;

  const _PaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.green.shade50,
        child: Icon(LucideIcons.check, size: 16, color: Colors.green.shade600),
      ),
      title: Text(payment.isAnonymous ? "Anonymous" : payment.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: payment.message != null && payment.message!.isNotEmpty
          ? Text(payment.message!, style: const TextStyle(fontSize: 11, color: Colors.grey))
          : null,
      trailing: Text("K${payment.amount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.green.shade700)),
    );
  }
}

class _PledgeDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Join Group", style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("How much do you pledge to contribute?", style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixText: "K ",
              hintText: "Amount",
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () {
            final amt = double.tryParse(ctrl.text);
            if (amt != null && amt > 0) Navigator.pop(context, amt);
          },
          child: const Text("JOIN"),
        ),
      ],
    );
  }
}

class _ContributionAmountDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Contribute", style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Enter amount to contribute", style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixText: "K ",
              hintText: "Amount",
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () {
            final amt = double.tryParse(ctrl.text);
            if (amt != null && amt > 0) Navigator.pop(context, amt);
          },
          child: const Text("PAY"),
        ),
      ],
    );
  }
}
