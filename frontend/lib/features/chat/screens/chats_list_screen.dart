import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/ws_service.dart';
import '../chat_repository.dart';
import 'chat_room_screen.dart';

/// Navy cards, circular avatars, gold online dot, 20-char preview.
class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({
    super.key,
    required this.repo,
    required this.ws,
    required this.myId,
  });

  final ChatRepository repo;
  final WsService ws;
  final String myId;

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  late Future<List<Conversation>> _future = widget.repo.conversations();

  Future<void> _refresh() async {
    setState(() => _future = widget.repo.conversations());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: MilColors.gold,
      backgroundColor: MilColors.navySurface,
      onRefresh: _refresh,
      child: FutureBuilder<List<Conversation>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: MilColors.gold));
          }
          final chats = snap.data ?? [];
          if (chats.isEmpty) {
            return ListView(
              // ListView so pull-to-refresh still works on empty state
              children: const [
                SizedBox(height: 160),
                Icon(Icons.forum_outlined,
                    size: 64, color: MilColors.goldDim),
                SizedBox(height: 16),
                Center(
                  child: Text('لا توجد محادثات بعد',
                      style: TextStyle(color: MilColors.textLo)),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ChatCard(
              chat: chats[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(
                    repo: widget.repo,
                    ws: widget.ws,
                    myId: widget.myId,
                    peerId: chats[i].peerId,
                    peerName: chats[i].peerName,
                    peerOnline: chats[i].isOnline,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatCard extends StatelessWidget {
  const _ChatCard({required this.chat, required this.onTap});

  final Conversation chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MilColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MilColors.navyBorder),
          ),
          child: Row(
            children: [
              // Avatar + gold online dot
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: MilColors.navyDeep,
                    child: Text(
                      chat.peerName.characters.first,
                      style: const TextStyle(
                        color: MilColors.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (chat.isOnline)
                    PositionedDirectional(
                      bottom: 0,
                      end: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: MilColors.gold,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: MilColors.navySurface, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            chat.peerName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: MilColors.textHi,
                            ),
                          ),
                        ),
                        if (chat.isOnline) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.bolt,
                              size: 14, color: MilColors.gold),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chat.lastMessagePreview ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: MilColors.textLo, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (chat.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: MilColors.gold,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${chat.unreadCount}',
                    style: const TextStyle(
                      color: MilColors.navyDeep,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
