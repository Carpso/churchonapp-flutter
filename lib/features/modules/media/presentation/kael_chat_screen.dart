import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/ai_chat_service.dart';

class KaelChatScreen extends ConsumerStatefulWidget {
  const KaelChatScreen({super.key});

  @override
  ConsumerState<KaelChatScreen> createState() => _KaelChatScreenState();
}

class _KaelChatScreenState extends ConsumerState<KaelChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _sessionId;
  String? _initError;
  bool _isLoading = false;
  bool _isStreaming = false;
  String _streamingBuffer = '';
  StreamSubscription<String>? _streamSubscription;
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
  }

  @override
  void dispose() {
    _avatarGlowController.dispose();
    _pulseController.dispose();
    _streamSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    setState(() => _isLoading = true);
    try {
      final id = await ref.read(aiChatServiceProvider).createSession("New Spiritual Inquiry");
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
    final stream = service.sendMessageStreaming(_sessionId!, content);

    _streamSubscription = stream.listen(
      (chunk) {
        if (!mounted) return;
        setState(() => _streamingBuffer += chunk);
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isStreaming = false;
          _streamingBuffer = '';
        });
      },
      onError: (error) {
        if (!mounted) return;
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
    final stream = service.regenerateStreaming(_sessionId!);

    _streamSubscription = stream.listen(
      (chunk) {
        if (!mounted) return;
        setState(() => _streamingBuffer += chunk);
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isStreaming = false;
          _streamingBuffer = '';
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isStreaming = false;
          _streamingBuffer = '';
        });
      },
    );
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : _sessionId == null
              ? _buildInitError()
              : Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<AiChatMessage>>(
                    stream: ref.read(aiChatServiceProvider).getMessagesStream(_sessionId!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.bot, size: 48, color: Colors.white24),
                              SizedBox(height: 16),
                              Text("Ask Kael anything",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                              SizedBox(height: 8),
                              Text("Your AI Bible study assistant is ready.",
                                style: TextStyle(color: Colors.white38)),
                            ],
                          ),
                        );
                      }
                      final messages = snapshot.data!;
                      final hasStreamingBubble = _isStreaming && _streamingBuffer.isNotEmpty && (messages.isEmpty || messages.last.role == 'user');

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(20),
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
                    color: isUser ? Colors.amber.withAlpha(200) : Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
                      bottomRight: isUser ? Radius.zero : const Radius.circular(20),
                    ),
                  ),
                  child: Text(
                    msg.content,
                    style: TextStyle(color: isUser ? Colors.white : Colors.white70, fontSize: 15, height: 1.4),
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
          // Regenerate button on last assistant message
          if (showRegenerate)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 6),
              child: GestureDetector(
                onTap: _isStreaming ? null : _regenerate,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.refreshCw,
                      size: 14,
                      color: _isStreaming ? Colors.white24 : Colors.amber.withAlpha(180),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Regenerate',
                      style: TextStyle(
                        color: _isStreaming ? Colors.white24 : Colors.amber.withAlpha(180),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
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
