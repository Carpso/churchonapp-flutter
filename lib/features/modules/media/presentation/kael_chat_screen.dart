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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty || _sessionId == null) return;
    
    final content = _controller.text.trim();
    _controller.clear();
    
    await ref.read(aiChatServiceProvider).sendMessage(_sessionId!, content);
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
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isUser = msg.role == 'user';
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 15),
                              padding: const EdgeInsets.all(15),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                              decoration: BoxDecoration(
                                color: isUser ? Theme.of(context).primaryColor : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                msg.content,
                                style: TextStyle(color: isUser ? Colors.white : Colors.black87),
                              ),
                            ),
                          );
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

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
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
            backgroundColor: Theme.of(context).primaryColor,
            child: IconButton(
              icon: const Icon(LucideIcons.send, color: Colors.white, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

