import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/ws_service.dart';
import '../../../l10n/app_localizations.dart';
import '../chat_repository.dart';
import 'chat_room_screen.dart';
import '../../../core/icons.dart';

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
      color: IronColors.gold,
      backgroundColor: IronColors.navySurface,
      onRefresh: _refresh,
      child: FutureBuilder<List<Conversation>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: IronColors.gold));
          }
          final chats = snap.data ?? [];
          if (chats.isEmpty) {
            // Fills the viewport so the state sits centred, while staying a
            // scrollable so pull-to-refresh still works with no items.
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IronEmptyState(
                    title: L.of(context).noChatsYet,
                    message: L.of(context).noChatsYetHint,
                    rings: 1,
                  ),
                ),
              ),
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
                    isSecret: false,
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
      color: IronColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: IronColors.navyBorder),
          ),
          child: Row(
            children: [
              // Avatar + gold online dot
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: IronColors.navyDeep,
                    child: Text(
                      chat.peerName.characters.first,
                      style: const TextStyle(
                        color: IronColors.gold,
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
                          color: IronColors.gold,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: IronColors.navySurface, width: 2.5),
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
                              color: IronColors.textHi,
                            ),
                          ),
                        ),
                        if (chat.isOnline) ...[
                          const SizedBox(width: 6),
                          const Icon(IronIcons.online,
                              size: IronIcons.sizeCompact, color: IronColors.gold),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chat.lastMessagePreview ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: IronColors.textLo, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (chat.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: IronColors.gold,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${chat.unreadCount}',
                    style: const TextStyle(
                      color: IronColors.navyDeep,
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
