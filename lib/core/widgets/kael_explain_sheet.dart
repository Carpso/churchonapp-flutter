import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Generates text with Kael AI through the `kael-ai` Edge Function.
///
/// [action] shapes the JSON response (`exegesis` / `summary` / `caption` etc.).
/// Returns `__RATE_LIMIT__` when throttled so the caller can offer a retry.
Future<String> kaelGenerate({
  required String prompt,
  String action = 'exegesis',
}) async {
  try {
    final res = await Supabase.instance.client.functions.invoke(
      'kael-ai',
      body: {'action': action, 'prompt': prompt},
    );
    final data = res.data as Map<String, dynamic>?;
    final text = (data?['response'] ?? '').toString().trim();
    return text.isEmpty
        ? 'Kael AI had nothing to add — seek the passage in context.'
        : text;
  } catch (e) {
    // 429 rate-limit surfaced with a friendly retry message.
    final message = e.toString().toLowerCase();
    final isRateLimit =
        message.contains('rate limit') || message.contains('429');
    return isRateLimit
        ? '__RATE_LIMIT__'
        : 'Kael AI is resting right now — please try again in a moment.';
  }
}

/// Shows a Kael AI result in a bottom sheet that NEVER closes on its own.
///
/// Root-cause fix for the "sheet disappears while I'm reading/scrolling" bug:
/// - [isDismissible] `false` and [enableDrag] `false`, so a stray barrier tap
///   or a drag can't dismiss it. Only the explicit CLOSE button pops the sheet
///   (the visual grip is decorative — it is not a drag target).
/// - The body is a dedicated `Flexible` + `SingleChildScrollView`, so scrolling
///   the result can never be interpreted as a sheet drag.
/// - The state lives in a real `StatefulWidget` (not a `StatefulBuilder` whose
///   builder re-ran `call()` and reset the `FutureBuilder` on every rebuild),
///   so the result is fetched once and stays put.
/// - The result is `SelectableText` (long-press to select) and every draft has
///   COPY / COPY ALL / REGENERATE, plus INSERT when [onInsert] is supplied.
Future<void> showKaelExplainSheet(
  BuildContext context, {
  required String prompt,
  String action = 'exegesis',
  String title = 'Kael AI',
  ValueChanged<String>? onInsert,
  String insertLabel = 'INSERT',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _KaelResultSheet(
      prompt: prompt,
      action: action,
      title: title,
      onInsert: onInsert,
      insertLabel: insertLabel,
    ),
  );
}

class _KaelResultSheet extends StatefulWidget {
  const _KaelResultSheet({
    required this.prompt,
    required this.action,
    required this.title,
    this.onInsert,
    this.insertLabel = 'INSERT',
  });

  final String prompt;
  final String action;
  final String title;
  final ValueChanged<String>? onInsert;
  final String insertLabel;

  @override
  State<_KaelResultSheet> createState() => _KaelResultSheetState();
}

class _KaelResultSheetState extends State<_KaelResultSheet> {
  final List<String> _variants = [];
  bool _loading = false;
  bool _rateLimited = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _rateLimited = false;
    });
    final text =
        await kaelGenerate(prompt: widget.prompt, action: widget.action);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (text == '__RATE_LIMIT__') {
        _rateLimited = true;
      } else {
        _variants.add(text);
      }
    });
  }

  Future<void> _copy(String text, {String note = 'Copied to clipboard'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(note), duration: const Duration(seconds: 2)),
    );
  }

  void _insert(String text) {
    widget.onInsert?.call(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Inserted into your field'),
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canInsert = widget.onInsert != null;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF151A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          // Visual grip only — enableDrag is false so the sheet cannot be
          // dragged away while the user reads or scrolls the result.
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
            child: Row(
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
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (_variants.isNotEmpty)
                  IconButton(
                    tooltip: 'Copy all',
                    icon: const Icon(LucideIcons.copy,
                        color: Colors.white70, size: 18),
                    onPressed: () => _copy(
                      _variants.join('\n\n———\n\n'),
                      note: 'All drafts copied',
                    ),
                  ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(LucideIcons.x, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_rateLimited) _buildRateLimit(),
                  for (var i = 0; i < _variants.length; i++)
                    _buildVariant(i, _variants[i], canInsert),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.amber,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Kael AI is writing…',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _variants.isEmpty
                            ? null
                            : () => _copy(
                                  _variants.join('\n\n———\n\n'),
                                  note: 'All drafts copied',
                                ),
                        icon: const Icon(LucideIcons.copy, size: 16),
                        label: const Text('COPY ALL'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _generate,
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        label: const Text('REGENERATE'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          side: const BorderSide(color: Colors.amber),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'CLOSE',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariant(int index, String text, bool canInsert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_variants.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'DRAFT ${index + 1}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          SelectableText(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _copy(text, note: 'Draft copied'),
                icon: const Icon(LucideIcons.copy, size: 15),
                label: const Text('COPY'),
                style: TextButton.styleFrom(foregroundColor: Colors.amber),
              ),
              if (canInsert)
                TextButton.icon(
                  onPressed: () => _insert(text),
                  icon: const Icon(LucideIcons.arrowDownToLine, size: 15),
                  label: Text(widget.insertLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRateLimit() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.clock, color: Colors.deepOrange, size: 16),
              SizedBox(width: 6),
              Text(
                'Kael AI is helping another member right now',
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
            'Kael AI handles up to 10 requests per minute. Wait a few seconds and tap REGENERATE.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
