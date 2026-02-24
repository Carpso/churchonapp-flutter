import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SovereignMatchmakingScreen extends StatefulWidget {
  const SovereignMatchmakingScreen({super.key});

  @override
  State<SovereignMatchmakingScreen> createState() => _SovereignMatchmakingScreenState();
}

class _SovereignMatchmakingScreenState extends State<SovereignMatchmakingScreen> {
  final List<Message> _messages = [];
  final TextEditingController _msgController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Realtime dummy data initially
    _messages.addAll([
      Message("Welcome to Sovereign connect! Start chatting with local kingdom singles.", isMe: false),
    ]);
  }

  void _sendMessage() {
    if (_msgController.text.trim().isEmpty) return;
    setState(() {
      _messages.add(Message(_msgController.text, isMe: true));
      _msgController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Sovereign Connect"),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () {},
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(LucideIcons.heartHandshake, color: Colors.orange),
                const SizedBox(width: 10),
                Text("Finding potential matches securely...", style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: msg.isMe ? Theme.of(context).primaryColor : Colors.white,
                      borderRadius: BorderRadius.circular(20).copyWith(
                        bottomRight: msg.isMe ? const Radius.circular(0) : const Radius.circular(20),
                        bottomLeft: msg.isMe ? const Radius.circular(20) : const Radius.circular(0),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5)
                      ]
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(color: msg.isMe ? Theme.of(context).colorScheme.secondary : Colors.black87),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.white,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(icon: const Icon(LucideIcons.imagePlus, color: Colors.grey), onPressed: () {}),
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    child: IconButton(
                      icon: Icon(LucideIcons.send, color: Theme.of(context).colorScheme.secondary, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class Message {
  final String text;
  final bool isMe;
  Message(this.text, {required this.isMe});
}
