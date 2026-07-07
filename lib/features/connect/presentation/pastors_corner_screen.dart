import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/network_service.dart';

class PastorsCornerScreen extends ConsumerStatefulWidget {
  const PastorsCornerScreen({super.key});

  @override
  ConsumerState<PastorsCornerScreen> createState() => _PastorsCornerScreenState();
}

class _PastorsCornerScreenState extends ConsumerState<PastorsCornerScreen> {
  final Set<String> _expandedIds = {};

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(pastorMessagesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Pastor's Corner"),
      ),
      body: messagesAsync.when(
        data: (messages) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(pastorMessagesProvider);
          },
          child: messages.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                    Center(
                      child: Column(
                        children: [
                          Icon(LucideIcons.mail, size: 60, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          const Text("No messages yet", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          const Text("Your pastor hasn't posted any messages yet.\nCheck back soon!", style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _buildMessageCard(messages[index]),
                ),
        ),
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.wifiOff, size: 50, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text("Error loading messages: $err", style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text("Retry"),
                onPressed: () => ref.invalidate(pastorMessagesProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageCard(PastorMessage message) {
    final isExpanded = _expandedIds.contains(message.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage: message.pastorPhoto != null ? NetworkImage(message.pastorPhoto!) : null,
                  child: message.pastorPhoto == null
                      ? Icon(LucideIcons.user, color: Colors.amber.shade700, size: 22)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message.pastorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(DateFormat.MMMd().format(message.createdAt), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                    ],
                  ),
                ),
                Icon(LucideIcons.messageCircle, size: 18, color: Colors.amber.shade300),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(message.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isExpanded ? message.content : message.excerpt,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.5),
                  maxLines: isExpanded ? null : 3,
                  overflow: isExpanded ? null : TextOverflow.ellipsis,
                ),
                if (message.content.length > message.excerpt.length) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedIds.remove(message.id);
                        } else {
                          _expandedIds.add(message.id);
                        }
                      });
                    },
                    child: Row(
                      children: [
                        Text(
                          isExpanded ? "Show less" : "Read more",
                          style: TextStyle(color: Colors.amber.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Icon(isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: Colors.amber.shade700),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
