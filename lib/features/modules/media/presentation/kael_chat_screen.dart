import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/ai_chat_service.dart';
import '../data/kael_settings.dart';

class KaelChatScreen extends ConsumerStatefulWidget {
  const KaelChatScreen({super.key});

  @override
  ConsumerState<KaelChatScreen> createState() => _KaelChatScreenState();
}

class _KaelChatScreenState extends ConsumerState<KaelChatScreen> with TickerProviderStateMixin {
  static const _suggestions = [
    'Give me a verse for today',
    'Explain the parable of the Good Samaritan',
    'How do I schedule a church event?',
    'Pray with me for strength',
    'What is my church\'s giving dashboard?',
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _sessionId;
  String? _initError;
  bool _isLoading = false;
  bool _isStreaming = false;
  String _streamingBuffer = '';
  Stream<List<AiChatMessage>>? _messagesStream;
  StreamSubscription<String>? _streamSubscription;
  Timer? _flushTimer;
  final List<String> _pendingChunks = [];
  late AnimationController _avatarGlowController;
  late Animation<double> _avatarGlowAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _avatarGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _avatarGlowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _avatarGlowController, curve: Curves.easeInOut),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initSession();
    // Hydrate Kael preferences (answer length, tone, translation, refs).
    ref.read(kaelSettingsProvider.notifier).load();
  }

  @override
  void dispose() {
    _avatarGlowController.dispose();
    _pulseController.dispose();
    _flushTimer?.cancel();
    _streamSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(aiChatServiceProvider);
      final id = await service.createSession("New Chat");
      _messagesStream = service.getMessagesStream(id);
      setState(() {
        _sessionId = id;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _initError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  /// Starts a brand-new conversation thread (professional chat hygiene).
  Future<void> _startNewChat() async {
    _streamSubscription?.cancel();
    _flushTimer?.cancel();
    _pendingChunks.clear();
    _controller.clear();
    await _initSession();
  }

  void _onStreamChunk(String chunk) {
    if (!mounted) return;
    _pendingChunks.add(chunk);
    _flushTimer ??= Timer(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      final joined = _pendingChunks.join();
      _pendingChunks.clear();
      _flushTimer = null;
      setState(() => _streamingBuffer += joined);
      _scrollToBottom();
    });
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty || _sessionId == null || _isStreaming) return;

    final content = _controller.text.trim();
    _controller.clear();

    setState(() {
      _isStreaming = true;
      _streamingBuffer = '';
    });

    _scrollToBottom();

    final service = ref.read(aiChatServiceProvider);
    final settings = ref.read(kaelSettingsProvider);
    final stream = service.sendMessageStreaming(
      _sessionId!,
      content,
      options: settings.toRequestOptions(),
      system: settings.toSystemDirective(),
    );

    _streamSubscription = stream.listen(
      (chunk) => _onStreamChunk(chunk),
      onDone: () {
        if (!mounted) return;
        _flushTimer?.cancel();
        _flushTimer = null;
        _pendingChunks.clear();
        setState(() {
          _isStreaming = false;
          _streamingBuffer = '';
        });
      },
      onError: (error) {
        if (!mounted) return;
        _flushTimer?.cancel();
        _flushTimer = null;
        _pendingChunks.clear();
        setState(() {
          _isStreaming = false;
          _streamingBuffer = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Stream error: $error")),
        );
      },
    );
  }

  void _regenerate() {
    if (_sessionId == null || _isStreaming) return;

    setState(() {
      _isStreaming = true;
      _streamingBuffer = '';
    });

    _scrollToBottom();

    final service = ref.read(aiChatServiceProvider);
    final settings = ref.read(kaelSettingsProvider);
    final stream = service.regenerateStreaming(
      _sessionId!,
      options: settings.toRequestOptions(),
      system: settings.toSystemDirective(),
    );

    _streamSubscription = stream.listen(
      (chunk) => _onStreamChunk(chunk),
      onDone: () {
        if (!mounted) return;
        _flushTimer?.cancel();
        _flushTimer = null;
        _pendingChunks.clear();
        setState(() {
          _isStreaming = false;
          _streamingBuffer = '';
        });
      },
      onError: (error) {
        if (!mounted) return;
        _flushTimer?.cancel();
        _flushTimer = null;
        _pendingChunks.clear();
        setState(() {
          _isStreaming = false;
          _streamingBuffer = '';
        });
      },
    );
  }

  /// Opens a session chosen from the History list and rebinds the live stream.
  Future<void> _openSession(AiChatSession session) async {
    if (session.id == _sessionId) return;
    _streamSubscription?.cancel();
    _flushTimer?.cancel();
    _pendingChunks.clear();

    final service = ref.read(aiChatServiceProvider);
    try {
      // Validates access + primes the transcript before the stream attaches.
      await service.loadSession(session.id);
    } catch (e) {
      debugPrint('[Kael] loadSession failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _sessionId = session.id;
      _messagesStream = service.getMessagesStream(session.id);
      _isStreaming = false;
      _streamingBuffer = '';
      _initError = null;
    });
    _scrollToBottom();
  }

  Future<void> _showHistorySheet() async {
    final service = ref.read(aiChatServiceProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF11162A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _KaelHistorySheet(
        service: service,
        currentSessionId: _sessionId,
        onOpen: (session) async {
          Navigator.of(sheetContext).pop();
          await _openSession(session);
        },
        onDeleted: (id) {
          if (id == _sessionId) _startNewChat();
        },
      ),
    );
  }

  Future<void> _showSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF11162A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(kaelSettingsProvider);
          final notifier = ref.read(kaelSettingsProvider.notifier);
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(LucideIcons.slidersHorizontal, color: Colors.amber, size: 20),
                      SizedBox(width: 10),
                      Text('Kael Settings',
                          style: TextStyle(
                              color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _settingsLabel('ANSWER LENGTH'),
                  Wrap(
                    spacing: 8,
                    children: KaelAnswerLength.values
                        .map((v) => _settingsChip(
                              label: v.label,
                              selected: settings.answerLength == v,
                              onTap: () => notifier.setAnswerLength(v),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  _settingsLabel('TONE'),
                  Wrap(
                    spacing: 8,
                    children: KaelTone.values
                        .map((v) => _settingsChip(
                              label: v.label,
                              selected: settings.tone == v,
                              onTap: () => notifier.setTone(v),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  _settingsLabel('PREFERRED BIBLE TRANSLATION'),
                  DropdownButtonFormField<String>(
                    initialValue: settings.preferredTranslation,
                    dropdownColor: const Color(0xFF11162A),
                    iconEnabledColor: Colors.white70,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withAlpha(10),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: kKaelTranslations.entries
                        .map((e) => DropdownMenuItem<String>(
                              value: e.key,
                              child: Text(e.value, style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) notifier.setPreferredTranslation(value);
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.includeReferences,
                    activeThumbColor: Colors.amber,
                    title: const Text('Include scripture references',
                        style: TextStyle(color: Colors.white, fontSize: 15)),
                    subtitle: const Text('Ask Kael to cite chapter and verse',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    onChanged: (value) => notifier.setIncludeReferences(value),
                  ),
                  const Divider(color: Colors.white12, height: 28),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.trash2, color: Colors.redAccent, size: 20),
                    title: const Text('Clear all chats',
                        style: TextStyle(color: Colors.redAccent, fontSize: 15)),
                    subtitle: const Text('Permanently delete every Kael conversation',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    onTap: () => _confirmClearAllChats(sheetContext),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _settingsLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      );

  Widget _settingsChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        color: selected ? Colors.black87 : Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: Colors.white.withAlpha(12),
      selectedColor: Colors.amber,
      side: BorderSide(color: selected ? Colors.amber : Colors.white24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Future<void> _confirmClearAllChats(BuildContext sheetContext) async {
    // Capture the sheet navigator BEFORE any async gap (the sheet's context is
    // not safe to use after an await).
    final sheetNavigator = Navigator.of(sheetContext);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF11162A),
        title: const Text('Clear all chats?', style: TextStyle(color: Colors.white)),
        content: const Text('Every Kael conversation will be permanently deleted.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete all', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(aiChatServiceProvider).clearAllSessions();
      if (!mounted) return;
      if (sheetNavigator.canPop()) sheetNavigator.pop();
      await _startNewChat();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All Kael chats cleared')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear chats: $e')),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildAnimatedAvatar({double radius = 16, bool showGlow = true}) {
    return AnimatedBuilder(
      animation: Listenable.merge([_avatarGlowAnimation, _pulseAnimation]),
      builder: (context, child) {
        return Container(
          width: radius * 2 + 8,
          height: radius * 2 + 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: showGlow
                ? [
                    BoxShadow(
                      color: Colors.amber.withAlpha((_avatarGlowAnimation.value * 120).toInt()),
                      blurRadius: 12 * _avatarGlowAnimation.value,
                      spreadRadius: 3 * _avatarGlowAnimation.value,
                    ),
                  ]
                : null,
          ),
          child: Transform.scale(
            scale: _pulseAnimation.value,
            child: CircleAvatar(
              radius: radius,
              backgroundColor: Colors.amber,
              backgroundImage: const AssetImage('assets/app_logo.png'),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.amber.withAlpha(150),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        title: Row(
          children: [
            _buildAnimatedAvatar(radius: 14, showGlow: false),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Kael AI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text("Assistant", style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Chat history",
            icon: const Icon(LucideIcons.history, color: Colors.white70, size: 20),
            onPressed: _isStreaming ? null : _showHistorySheet,
          ),
          IconButton(
            tooltip: "Kael settings",
            icon: const Icon(LucideIcons.settings, color: Colors.white70, size: 20),
            onPressed: _showSettingsSheet,
          ),
          IconButton(
            tooltip: "New chat",
            icon: const Icon(LucideIcons.plus, color: Colors.white70, size: 20),
            onPressed: _isStreaming ? null : _startNewChat,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : _sessionId == null
              ? _buildInitError()
              : Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<AiChatMessage>>(
                    stream: _messagesStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError && !snapshot.hasData) {
                        return Center(
                          child: Text("Failed to load messages: ${snapshot.error}",
                            style: const TextStyle(color: Colors.white54)),
                        );
                      }
                      // Show the suggestion templates whenever the thread is
                      // actually empty — not only before the first frame. The
                      // messages stream emits an empty list immediately, so a
                      // `!snapshot.hasData` guard made the chips disappear.
                      if ((snapshot.data ?? const <AiChatMessage>[]).isEmpty &&
                          !_isStreaming) {
                        return Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Theme-aware colours — the hardcoded whites were
                                // invisible on the (light) default background.
                                Icon(LucideIcons.bot,
                                    size: 48,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.25)),
                                const SizedBox(height: 16),
                                Text("Ask Kael anything",
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurface)),
                                const SizedBox(height: 8),
                                Text("Your AI Bible study assistant remembers this conversation.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6))),
                                const SizedBox(height: 24),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: _suggestions.map((s) => ActionChip(
                                    label: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    labelStyle: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    side: BorderSide(
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    onPressed: _isStreaming ? null : () {
                                      _controller.text = s;
                                      _sendMessage();
                                    },
                                  )).toList(),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final messages = snapshot.data ?? const <AiChatMessage>[];
                      final hasStreamingBubble = _isStreaming && _streamingBuffer.isNotEmpty && (messages.isEmpty || messages.last.role == 'user');

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        itemCount: messages.length + (hasStreamingBubble ? 1 : 0) + (_isStreaming && !hasStreamingBubble ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Typing indicator (before any streaming text appears)
                          if (index == messages.length && _isStreaming && !hasStreamingBubble) {
                            return _buildTypingIndicator();
                          }
                          // Streaming bubble (live text)
                          if (index == messages.length && hasStreamingBubble) {
                            return _buildStreamingBubble();
                          }
                          final msg = messages[index];
                          final isUser = msg.role == 'user';
                          final isLastAssistant = !isUser && index == messages.length - 1 && !_isStreaming;

                          return _buildMessageBubble(msg, isUser, showRegenerate: isLastAssistant);
                        },
                      );
                    },
                  ),
                ),
                _buildInput(),
              ],
            ),
    );
  }

  Widget _buildMessageBubble(AiChatMessage msg, bool isUser, {bool showRegenerate = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser)
                _buildAnimatedAvatar(radius: 16),
              if (!isUser) const SizedBox(width: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(15),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFFFFD700) : Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
                      bottomRight: isUser ? Radius.zero : const Radius.circular(20),
                    ),
                  ),
                  child: isUser
                      ? Text(
                          msg.content,
                          // Brand yellow bubble needs DARK text — white on amber was
                          // unreadable.
                          style: const TextStyle(color: Colors.black87, fontSize: 15, height: 1.4),
                        )
                      : SelectableText(
                          msg.content,
                          style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                        ),
                ),
              ),
              if (isUser) const SizedBox(width: 10),
              if (isUser)
                CircleAvatar(
                  backgroundColor: Colors.white.withAlpha(20),
                  radius: 16,
                  child: const Icon(LucideIcons.user, size: 18, color: Colors.white54),
                ),
            ],
          ),
          // Assistant result actions: COPY always, REGENERATE on the last reply.
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _assistantAction(
                    LucideIcons.copy,
                    'Copy',
                    () => _copyMessage(msg.content),
                  ),
                  if (showRegenerate) ...[
                    const SizedBox(width: 16),
                    _assistantAction(
                      LucideIcons.refreshCw,
                      'Regenerate',
                      _isStreaming ? null : _regenerate,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _assistantAction(IconData icon, String label, VoidCallback? onTap) {
    final color = onTap == null ? Colors.white24 : Colors.amber.withAlpha(180);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  Widget _buildStreamingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildAnimatedAvatar(radius: 16),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(15),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(15),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      _streamingBuffer,
                      style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildLiveCursor(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveCursor() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
        return Opacity(
          opacity: value > 0.5 ? 1.0 : 0.3,
          child: Container(
            width: 2,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          _buildAnimatedAvatar(radius: 16),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return AnimatedContainer(
          duration: Duration(milliseconds: 300 + (index * 100)),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.amber.withAlpha((value * 255).toInt()),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildInitError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.alertCircle, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              "Couldn't start a chat session",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              _initError ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _initError = null;
                  _isLoading = true;
                });
                _initSession();
              },
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber,
                side: const BorderSide(color: Colors.amber),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(15))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_isStreaming,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Ask Kael anything...",
                  hintStyle: const TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white.withAlpha(10),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 10),
            CircleAvatar(
              backgroundColor: _isStreaming ? Colors.white.withAlpha(20) : Colors.amber,
              child: IconButton(
                icon: Icon(
                  _isStreaming ? LucideIcons.hourglass : LucideIcons.send,
                  color: _isStreaming ? Colors.white38 : Colors.white,
                  size: 20,
                ),
                onPressed: _isStreaming ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Relative timestamp for the History list (e.g. "3h ago").
String _kaelTimeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

/// Bottom-sheet list of the user's chat sessions, newest activity first.
/// Tapping opens a session; each row can be renamed or deleted.
class _KaelHistorySheet extends StatefulWidget {
  final AiChatService service;
  final String? currentSessionId;
  final Future<void> Function(AiChatSession session) onOpen;
  final ValueChanged<String>? onDeleted;

  const _KaelHistorySheet({
    required this.service,
    required this.onOpen,
    this.currentSessionId,
    this.onDeleted,
  });

  @override
  State<_KaelHistorySheet> createState() => _KaelHistorySheetState();
}

class _KaelHistorySheetState extends State<_KaelHistorySheet> {
  late Future<List<AiChatSession>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.fetchSessions();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.service.fetchSessions());
    await _future;
  }

  Future<void> _rename(AiChatSession session) async {
    final controller = TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11162A),
        title: const Text('Rename chat', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Chat title',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    try {
      await widget.service.renameSession(session.id, newTitle);
    } catch (e) {
      debugPrint('[Kael] rename failed: $e');
    }
    if (mounted) await _refresh();
  }

  Future<void> _delete(AiChatSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11162A),
        title: const Text('Delete chat?', style: TextStyle(color: Colors.white)),
        content: Text('"${session.title}" and its messages will be permanently deleted.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.deleteSession(session.id);
      widget.onDeleted?.call(session.id);
    } catch (e) {
      debugPrint('[Kael] delete failed: $e');
    }
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Icon(LucideIcons.history, color: Colors.amber, size: 20),
                SizedBox(width: 10),
                Text('Chat History',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: FutureBuilder<List<AiChatSession>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.amber));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.alertCircle, color: Colors.white24, size: 40),
                          const SizedBox(height: 12),
                          Text('Could not load history\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white54, fontSize: 13)),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(LucideIcons.refreshCw, size: 16),
                            label: const Text('Retry'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.amber,
                              side: const BorderSide(color: Colors.amber),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final sessions = snapshot.data ?? const <AiChatSession>[];
                if (sessions.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No chats yet. Ask Kael anything to start one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ),
                  );
                }
                return RefreshIndicator(
                  color: Colors.amber,
                  backgroundColor: const Color(0xFF11162A),
                  onRefresh: _refresh,
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isCurrent = session.id == widget.currentSessionId;
                      return ListTile(
                        leading: Icon(
                          LucideIcons.messageSquare,
                          color: isCurrent ? Colors.amber : Colors.white54,
                          size: 20,
                        ),
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? Colors.amber : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _kaelTimeAgo(session.updatedAt),
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(LucideIcons.moreVertical, color: Colors.white38, size: 18),
                          color: const Color(0xFF1B2138),
                          onSelected: (value) {
                            if (value == 'rename') {
                              _rename(session);
                            } else if (value == 'delete') {
                              _delete(session);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename', style: TextStyle(color: Colors.white)),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                        onTap: () {
                          widget.onOpen(session);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
