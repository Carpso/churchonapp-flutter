import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:just_audio/just_audio.dart';
import 'package:church_on_app/core/services/coins_service.dart';

class KidsAudioPlayer extends ConsumerStatefulWidget {
  final String title;
  final String? audioUrl;
  final String storyTitle;
  final VoidCallback onComplete;

  const KidsAudioPlayer({
    super.key,
    required this.title,
    this.audioUrl,
    this.storyTitle = '',
    required this.onComplete,
  });

  @override
  ConsumerState<KidsAudioPlayer> createState() => _KidsAudioPlayerState();
}

class _KidsAudioPlayerState extends ConsumerState<KidsAudioPlayer> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = true;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 1);
  int _sleepMinutes = 0;
  bool _quizShown = false;
  int _quizScore = 0;
  int _quizIndex = 0;

  static const _quizQuestions = [
    {'q': 'What did David use to defeat Goliath?', 'answers': ['Sword', 'Sling and stone', 'Spear', 'Bow'], 'correct': 1},
    {'q': 'How many days and nights did it rain during Noah\'s flood?', 'answers': ['7', '12', '40', '100'], 'correct': 2},
    {'q': 'What did God create on the first day?', 'answers': ['Animals', 'Light', 'Man', 'Trees'], 'correct': 1},
    {'q': 'Who was thrown into the lions\' den?', 'answers': ['Moses', 'David', 'Daniel', 'Joseph'], 'correct': 2},
    {'q': 'How many loaves and fish fed the 5000?', 'answers': ['3 and 1', '5 and 2', '7 and 3', '10 and 5'], 'correct': 1},
    {'q': 'What sea did Moses part?', 'answers': ['Dead Sea', 'Red Sea', 'Sea of Galilee', 'Mediterranean'], 'correct': 1},
  ];

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (widget.audioUrl == null || widget.audioUrl!.isEmpty) {
      setState(() { _isLoading = false; _error = 'No audio available'; });
      return;
    }
    try {
      await _player.setUrl(widget.audioUrl!);
      _player.positionStream.listen((p) => mounted ? setState(() => _position = p) : null);
      _player.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _duration = d);
      });
      _player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() => _isPlaying = state.playing);
        if (state.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
          _showQuiz();
        }
      });
      setState(() { _isLoading = false; _error = null; });
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _playPause() {
    if (_isPlaying) { _player.pause(); } else { _player.play(); }
  }

  void _seekRelative(Duration delta) {
    final newMs = (_position.inMilliseconds + delta.inMilliseconds).clamp(0, _duration.inMilliseconds);
    _player.seek(Duration(milliseconds: newMs));
  }

  void _setSleepTimer(int minutes) {
    setState(() => _sleepMinutes = minutes);
    if (minutes > 0) {
      Future.delayed(Duration(minutes: minutes), () {
        if (mounted && _isPlaying) {
          _player.pause();
          setState(() => _sleepMinutes = 0);
        }
      });
    }
  }

  void _showQuiz() {
    if (_quizShown) return;
    setState(() { _quizShown = true; _quizIndex = 0; _quizScore = 0; });
    _askQuestion();
  }

  void _askQuestion() {
    if (_quizIndex >= _quizQuestions.length) {
      _finishQuiz();
      return;
    }
    final q = _quizQuestions[_quizIndex];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [const Icon(LucideIcons.helpCircle, color: Colors.purple), const SizedBox(width: 8), Text('Quiz ${_quizIndex + 1}/${_quizQuestions.length}', style: const TextStyle(fontSize: 16))]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q['q'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...(q['answers'] as List<String>).asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (e.key == (q['correct'] as int)) {
                  setState(() => _quizScore++);
                }
                setState(() => _quizIndex++);
                _askQuestion();
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
              child: Text(e.value),
            ),
          )),
        ]),
      ),
    );
  }

  Future<void> _finishQuiz() async {
    final passed = _quizScore >= (_quizQuestions.length / 2).ceil();
    if (passed) {
      try {
        await ref.read(coinsServiceProvider).addAttendanceCoins();
      } catch (_) {}
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [Icon(passed ? LucideIcons.trophy : LucideIcons.star, color: passed ? Colors.amber : Colors.blue), const SizedBox(width: 8), Text(passed ? 'Great Job!' : 'Good Try!')]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$_quizScore/${_quizQuestions.length} correct', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: passed ? Colors.green : Colors.orange)),
          const SizedBox(height: 8),
          Text(passed ? 'You earned bonus coins! 🪙' : 'Listen again to improve your score!', style: const TextStyle(fontSize: 13, color: Colors.grey)),
          if (widget.storyTitle.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 12), child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                const Text('Parent Discussion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(_discussionPrompt(widget.storyTitle), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            )),
        ]),
        actions: [TextButton(onPressed: () { Navigator.pop(ctx); widget.onComplete(); }, child: const Text('Done'))],
      ),
    );
  }

  String _discussionPrompt(String story) {
    switch (story.toLowerCase().replaceAll(' ', '_')) {
      case 'david_and_goliath': return 'Ask your child: "What are the giants in your life that you need God\'s help with?"';
      case 'noah_and_the_ark': return 'Talk about: "How does God protect those who trust and obey Him?"';
      case 'jonah_and_the_big_fish': return 'Discuss: "Have you ever tried to run from something God wanted you to do?"';
      case 'the_birth_of_jesus': return 'Ask: "What gift would you bring baby Jesus, and why?"';
      default: return 'Ask your child: "What did you learn from this story? How can you apply it this week?"';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0;

    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            if (_error != null) Center(child: Text('⚠️ $_error', style: const TextStyle(color: Colors.red))),

            if (!_isLoading && _error == null) ...[
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(theme.primaryColor), minHeight: 6),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_formatDuration(_position), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(_formatDuration(_duration), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),

              // Controls
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(icon: const Icon(LucideIcons.skipBack), onPressed: () => _seekRelative(const Duration(seconds: -10))),
                const SizedBox(width: 16),
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor),
                  child: IconButton(icon: Icon(_isPlaying ? LucideIcons.pause : LucideIcons.play, color: Colors.white), onPressed: _playPause, iconSize: 28),
                ),
                const SizedBox(width: 16),
                IconButton(icon: const Icon(LucideIcons.skipForward), onPressed: () => _seekRelative(const Duration(seconds: 10))),
              ]),

              // Sleep timer
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(LucideIcons.moon, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                ...([15, 30, 45].map((m) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text('${m}m', style: TextStyle(fontSize: 11, color: _sleepMinutes == m ? Colors.white : Colors.grey)),
                    selected: _sleepMinutes == m,
                    selectedColor: Colors.indigo,
                    onSelected: (_) => _setSleepTimer(_sleepMinutes == m ? 0 : m),
                    visualDensity: VisualDensity.compact,
                  ),
                ))),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
