import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/pvp_service.dart';

class QuizInviteHandlerScreen extends ConsumerStatefulWidget {
  final String matchId;
  const QuizInviteHandlerScreen({super.key, required this.matchId});

  @override
  ConsumerState<QuizInviteHandlerScreen> createState() => _QuizInviteHandlerScreenState();
}

class _QuizInviteHandlerScreenState extends ConsumerState<QuizInviteHandlerScreen> {
  String _status = 'Joining challenge...';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _joinMatch();
  }

  Future<void> _joinMatch() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) {
        setState(() { _status = 'Please log in to join a quiz challenge.'; _error = true; });
        return;
      }

      final res = await client
          .from('pvp_matches')
          .select()
          .eq('id', widget.matchId)
          .maybeSingle();

      if (res == null) {
        setState(() { _status = 'This challenge no longer exists.'; _error = true; });
        return;
      }

      final match = PvPMatch.fromMap(res);
      if (match.status != 'pending') {
        setState(() { _status = 'This challenge has already been accepted or completed.'; _error = true; });
        return;
      }

      if (match.player1Id == uid) {
        if (mounted) {
          context.pushReplacement('/quiz/arena', extra: {
            'mode': 'Invite',
            'pvpMatch': match,
          });
        }
        return;
      }

      final pvpService = ref.read(pvpServiceProvider);
      final updated = await pvpService.joinByInvite(widget.matchId);
      if (updated == null || !mounted) {
        if (mounted) setState(() { _status = 'Failed to join challenge. Try again.'; _error = true; });
        return;
      }

      if (mounted) {
        context.pushReplacement('/quiz/arena', extra: {
          'mode': 'Invite',
          'pvpMatch': updated,
        });
      }
    } catch (e) {
      if (mounted) setState(() { _status = 'Failed to join challenge: $e'; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error) ...[
              const Icon(LucideIcons.alertTriangle, color: Colors.amber, size: 48),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => context.go('/'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                child: const Text('Go Home', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ] else ...[
              const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 3)),
              const SizedBox(height: 20),
              const Text('Joining Bible Quiz Challenge...',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }
}