import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'chat_screen.dart';

/// Admin-only inbox screen showing all client conversations.
class ConversationsListScreen extends StatelessWidget {
  const ConversationsListScreen({super.key});

  static const Color _navy = Color(0xFF1C2D5E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white12),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('conversations')
            .orderBy('lastMessageAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: _navy.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chat_bubble_outline,
                        size: 40, color: _navy.withOpacity(0.4)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No conversations yet',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _navy),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Clients will appear here once they send a message',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 72, endIndent: 0),
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final clientId = docs[i].id;
              final clientName =
                  data['clientName'] as String? ?? 'Client';
              final clientPhoto =
                  data['clientPhoto'] as String?;
              final lastMessage =
                  data['lastMessage'] as String? ?? '';
              final lastMessageAt =
                  data['lastMessageAt'] as Timestamp?;
              final unread =
                  (data['unreadAdmin'] as int? ?? 0);
              final lastSenderRole =
                  data['lastSenderRole'] as String? ?? '';

              return _ConversationTile(
                clientId: clientId,
                clientName: clientName,
                clientPhoto: clientPhoto,
                lastMessage: lastMessage,
                lastMessageAt: lastMessageAt,
                unreadCount: unread,
                lastSenderRole: lastSenderRole,
              );
            },
          );
        },
      ),
    );
  }
}

// ── conversation tile ──────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  final String clientId;
  final String clientName;
  final String? clientPhoto;
  final String lastMessage;
  final Timestamp? lastMessageAt;
  final int unreadCount;
  final String lastSenderRole;

  static const Color _navy = Color(0xFF1C2D5E);

  const _ConversationTile({
    required this.clientId,
    required this.clientName,
    required this.clientPhoto,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.lastSenderRole,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;
    // Prefix "You: " when the last message was from the admin
    final preview = lastSenderRole == 'admin'
        ? 'You: $lastMessage'
        : lastMessage;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            clientId: clientId,
            clientName: clientName,
            clientPhotoUrl: clientPhoto,
            isAdmin: true,
          ),
        ),
      ),
      child: Container(
        color: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 27,
              backgroundColor: _navy.withOpacity(0.1),
              backgroundImage:
                  clientPhoto != null ? NetworkImage(clientPhoto!) : null,
              child: clientPhoto == null
                  ? Text(
                      clientName.isNotEmpty
                          ? clientName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Name + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clientName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasUnread
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: hasUnread
                          ? Colors.black87
                          : Colors.grey[500],
                      fontWeight: hasUnread
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Time + badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (lastMessageAt != null)
                  Text(
                    _timeLabel(lastMessageAt!.toDate()),
                    style: TextStyle(
                      fontSize: 11,
                      color: hasUnread ? _navy : Colors.grey[400],
                      fontWeight: hasUnread
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                const SizedBox(height: 4),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unreadCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  const SizedBox(height: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('MMM d').format(dt);
  }
}
