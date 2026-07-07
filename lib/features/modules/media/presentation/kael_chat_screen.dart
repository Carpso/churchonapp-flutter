import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/ai_chat_service.dart';

class KaelChatScreen extends ConsumerStatefulWidget {
  const KaelChatScreen({super.key});

  @override
  ConsumerState<KaelChatScreen> createState() => _KaelChatScreenState();
}

class _KaelChatScreenState extends ConsumerState<KaelChatScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _sessionId;
  bool _isLoading = false;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _initSession();
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
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty || _sessionId == null) return;

    final content = _controller.text.trim();
    _controller.clear();

    setState(() => _isTyping = true);
    try {
      await ref.read(aiChatServiceProvider).sendMessage(_sessionId!, content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
    if (mounted) setState(() => _isTyping = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.amber,
              radius: 12,
              child: Text("K", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            SizedBox(width: 10),
            Text("Kael AI Assistant", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<AiChatMessage>>(
                    stream: ref.read(aiChatServiceProvider).getMessagesStream(_sessionId!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final messages = snapshot.data!;
                      return ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: messages.length + (_isTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == messages.length && _isTyping) {
                            return _buildTypingIndicator();
                          }
                          final msg = messages[index];
                          final isUser = msg.role == 'user';
                          return _buildMessageBubble(msg, isUser);
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

  Widget _buildMessageBubble(AiChatMessage msg, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            const CircleAvatar(
              backgroundColor: Colors.amber,
              radius: 16,
              child: Text("K", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          if (!isUser) const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(15),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
              decoration: BoxDecoration(
                color: isUser ? Theme.of(context).primaryColor : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
                  bottomRight: isUser ? Radius.zero : const Radius.circular(20),
                ),
              ),
              child: Text(
                msg.content,
                style: TextStyle(color: isUser ? Colors.white : Colors.black87),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 10),
          if (isUser)
            CircleAvatar(
              backgroundColor: Colors.grey.shade300,
              radius: 16,
              child: const Icon(LucideIcons.user, size: 18, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.amber,
            radius: 16,
            child: Text("K", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomRight: const Radius.circular(20),
              ),
            ),
            child: Text("Kael is typing...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_isTyping,
              decoration: InputDecoration(
                hintText: "Ask Kael anything...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            backgroundColor: _isTyping ? Colors.grey : Theme.of(context).primaryColor,
            child: IconButton(
              icon: const Icon(LucideIcons.send, color: Colors.white, size: 20),
              onPressed: _isTyping ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

