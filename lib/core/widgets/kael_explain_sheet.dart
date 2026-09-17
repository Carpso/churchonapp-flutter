import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reusable contextual "Ask Kael" assistant sheet.
///
/// Mirrors the `_showKaelExplain` pattern from the Bible-quiz results screen:
/// calls the `kael-ai` Edge Function and renders the answer in a dark branded
/// bottom sheet with a loading spinner and a rate-limit retry.
///
/// [action] is the Edge Function action used to shape the response. `exegesis`
/// and `summary` both return `{"response": "..."}` JSON.
Future<void> showKaelExplainSheet(
  BuildContext context, {
  required String prompt,
  String action = 'exegesis',
  String title = 'Kael explains',
}) {
  Future<String> call() async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'kael-ai',
        body: {'action': action, 'prompt': prompt},
      );
      final data = res.data as Map<String, dynamic>?;
      final text = (data?['response'] ?? '').toString().trim();
      return text.isEmpty
          ? 'Kael had nothing to add — seek the passage in context.'
          : text;
    } catch (e) {
      // 429 rate-limit surfaced with a friendly retry message.
      final message = e.toString().toLowerCase();
      final isRateLimit = message.contains('rate limit') || message.contains('429');
      return isRateLimit
          ? '__RATE_LIMIT__'
          : 'Kael is resting right now — please try again in a moment.';
    }
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        late Future<String> future;
        future = call();
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: Color(0xFF151A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(LucideIcons.sparkles,
                          color: Colors.amber, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FutureBuilder<String>(
                  future: future,
                  builder: (c, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.amber,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }
                    final text = snap.data ?? '';
                    if (text == '__RATE_LIMIT__') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(LucideIcons.clock,
                                    color: Colors.deepOrange, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Kael is helping another member right now',
                                  style: TextStyle(
                                    color: Colors.deepOrange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Kael answers up to 10 requests per minute. Wait a few seconds and try again.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  setSheetState(() => future = call()),
                              icon: const Icon(LucideIcons.refreshCw, size: 16),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
