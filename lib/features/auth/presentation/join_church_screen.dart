import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/auth_provider.dart';

class JoinChurchScreen extends ConsumerWidget {
  final String? churchId;
  final String? churchSlug;

  const JoinChurchScreen({super.key, this.churchId, this.churchSlug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFFAEB),
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

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(title: const Text("Join Church")),
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle, size: 64, color: Colors.green),
            const SizedBox(height: 20),
            const Text("You're already signed in!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text("Go to the church selection page to choose or search for your church.", textAlign: TextAlign.center),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => context.go('/select-church'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(200, 50)),
              child: const Text("Select Church"),
            ),
          ],
        ),
      ),
    );
  }
}
