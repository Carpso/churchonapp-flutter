import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/call_service.dart';
import 'audio_call_screen.dart';

class IncomingCallScreen extends ConsumerWidget {
  final CallSession callSession;

  const IncomingCallScreen({super.key, required this.callSession});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 0.9,
                colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.lock, color: Colors.greenAccent, size: 12),
                      SizedBox(width: 6),
                      Text('End-to-End Encrypted',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                CircleAvatar(
                  radius: 70,
                  backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=${callSession.callerId}'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Incoming Call',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Audio Call',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white54,
                  ),
                ),
                const Spacer(flex: 2),
                Container(
                  margin: const EdgeInsets.fromLTRB(24, 0, 24, 60),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          await ref.read(callServiceProvider).rejectCall(callSession.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 20)],
                              ),
                              child: const Icon(LucideIcons.phoneOff, color: Colors.white, size: 26),
                            ),
                            const SizedBox(height: 8),
                            const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AudioCallScreen(
                                userName: "Incoming Spiritual Call",
                                userAvatar: "https://i.pravatar.cc/150?u=${callSession.callerId}",
                                callSession: callSession,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.4), blurRadius: 20)],
                              ),
                              child: const Icon(LucideIcons.phone, color: Colors.white, size: 26),
                            ),
                            const SizedBox(height: 8),
                            const Text('Accept', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
