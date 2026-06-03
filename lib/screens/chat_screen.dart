import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// Shared chat screen used by both client and admin.
/// [clientId]  — always the client's UID (conversation document ID).
/// [isAdmin]   — true when the trainer is viewing.
class ChatScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  final String? clientPhotoUrl;
  final bool isAdmin;

  const ChatScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.clientPhotoUrl,
    required this.isAdmin,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _isSending = false;

  static const Color _navy = Color(0xFF1C2D5E);

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initConversation();
    _markAsRead();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// On first open by the client, stamp their profile info onto the
  /// conversation document so the admin inbox can display it.
  Future<void> _initConversation() async {
    if (widget.isAdmin) return;
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _fs.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      await _fs.collection('conversations').doc(widget.clientId).set({
        'clientId': widget.clientId,
        'clientName': data['name'] ?? widget.clientName,
        'clientPhoto': data['profileImage'],
        'clientEmail': data['email'] ?? user.email ?? '',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Reset unread counter for the current viewer when they open the screen.
  Future<void> _markAsRead() async {
    final field = widget.isAdmin ? 'unreadAdmin' : 'unreadClient';
    try {
      await _fs.collection('conversations').doc(widget.clientId).set(
        {field: 0},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    _textCtrl.clear();
    setState(() => _isSending = true);

    try {
      final uid = _auth.currentUser!.uid;
      final role = widget.isAdmin ? 'admin' : 'client';
      final batch = _fs.batch();

      // 1. Add message document
      final msgRef = _fs
          .collection('conversations')
          .doc(widget.clientId)
          .collection('messages')
          .doc();

      batch.set(msgRef, {
        'senderId': uid,
        'senderRole': role,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'type': 'text',
      });

      // 2. Update conversation meta (last message + unread counter)
      final convRef =
          _fs.collection('conversations').doc(widget.clientId);

      batch.set(convRef, {
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderRole': role,
        if (widget.isAdmin)
          'unreadClient': FieldValue.increment(1)
        else
          'unreadAdmin': FieldValue.increment(1),
      }, SetOptions(merge: true));

      await batch.commit();

      // Scroll to the latest message (list is reversed)
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final otherName =
        widget.isAdmin ? widget.clientName : 'Kenny Sims';
    final otherPhoto = widget.isAdmin ? widget.clientPhotoUrl : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: Colors.white24,
              backgroundImage:
                  otherPhoto != null ? NetworkImage(otherPhoto) : null,
              child: otherPhoto == null
                  ? Text(
                      otherName.isNotEmpty
                          ? otherName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(otherName,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const Text('Flex Facility',
                      style:
                          TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputBar(),
        ],
      ),
    );
  }

  // ── message list ──────────────────────────────────────────────────────────

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _fs
          .collection('conversations')
          .doc(widget.clientId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(150)
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
                Icon(Icons.chat_bubble_outline,
                    size: 64, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text('No messages yet',
                    style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  'Send a message to start the conversation',
                  style:
                      TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
          );
        }

        // Mark messages as read whenever new ones arrive
        _markAsRead();

        return ListView.builder(
          controller: _scrollCtrl,
          reverse: true,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data =
                docs[i].data() as Map<String, dynamic>;
            final role = data['senderRole'] as String? ?? '';
            final isMe = widget.isAdmin
                ? role == 'admin'
                : role == 'client';
            final showDate = _shouldShowDate(docs, i);

            // System messages get a different widget
            if (role == 'system') {
              return _SystemMessageBubble(
                data: data,
                showDate: showDate,
              );
            }

            return _MessageBubble(
              data: data,
              isMe: isMe,
              showDate: showDate,
            );
          },
        );
      },
    );
  }

  bool _shouldShowDate(List<QueryDocumentSnapshot> docs, int i) {
    if (i == docs.length - 1) return true;
    final curr = (docs[i].data() as Map<String, dynamic>)['timestamp']
        as Timestamp?;
    final prev = (docs[i + 1].data() as Map<String, dynamic>)['timestamp']
        as Timestamp?;
    if (curr == null || prev == null) return false;
    return !DateUtils.isSameDay(
        curr.toDate().toLocal(), prev.toDate().toLocal());
  }

  // ── input bar ─────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x18000000),
              blurRadius: 8,
              offset: Offset(0, -2))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _textCtrl,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: Colors.grey),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                  color: _navy, shape: BoxShape.circle),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── bubble widget ─────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final bool showDate;

  static const Color _navy = Color(0xFF1C2D5E);

  const _MessageBubble({
    required this.data,
    required this.isMe,
    required this.showDate,
  });

  @override
  Widget build(BuildContext context) {
    final text = data['text'] as String? ?? '';
    final ts = data['timestamp'] as Timestamp?;
    final time = ts != null
        ? DateFormat('h:mm a').format(ts.toDate().toLocal())
        : '';
    final isRead = data['read'] as bool? ?? false;

    return Column(
      children: [
        if (showDate && ts != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _dateLabel(ts.toDate().toLocal()),
                style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        Align(
          alignment:
              isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(
              bottom: 4,
              left: isMe ? 56 : 0,
              right: isMe ? 0 : 56,
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? _navy : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        color: isMe
                            ? Colors.white60
                            : Colors.grey[400],
                        fontSize: 11,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isRead ? Icons.done_all : Icons.done,
                        size: 14,
                        color: isRead
                            ? Colors.lightBlueAccent
                            : Colors.white60,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(dt, now)) return 'Today';
    if (DateUtils.isSameDay(
        dt, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return DateFormat('MMMM d, yyyy').format(dt);
  }
}

// ---------------------------------------------------------------------------
// System message widget — centred pill with icon + text
// ---------------------------------------------------------------------------

class _SystemMessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool showDate;

  const _SystemMessageBubble({
    required this.data,
    required this.showDate,
  });

  @override
  Widget build(BuildContext context) {
    final text = data['text'] as String? ?? '';
    final ts = data['timestamp'] as Timestamp?;
    final time = ts != null
        ? DateFormat('h:mm a').format(ts.toDate().toLocal())
        : '';

    return Column(
      children: [
        if (showDate && ts != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _dateLabel(ts.toDate().toLocal()),
                style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBBC8FF), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF1C2D5E),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                time,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(dt, now)) return 'Today';
    if (DateUtils.isSameDay(dt, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return DateFormat('MMMM d, yyyy').format(dt);
  }
}
