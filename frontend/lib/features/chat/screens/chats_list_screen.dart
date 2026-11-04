import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/ws_service.dart';
import '../../../l10n/app_localizations.dart';
import '../chat_repository.dart';
import '../local/message_store.dart';
import 'chat_room_screen.dart';
import '../../../core/icons.dart';

/// Navy cards, circular avatars, gold online dot, and a preview the server
/// never sees.
///
/// The preview is read from this device's decrypted history, not from the
/// conversation payload. The server holds ciphertext and no key; it used to
/// return the first twenty characters of the envelope and this list drew them
/// as though they were words.
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

/// A conversation from the server, paired with the last thing this device can
/// actually read in it.
typedef _Listed = ({Conversation chat, String? preview});

class _ChatsListScreenState extends State<ChatsListScreen> {
  late Future<List<_Listed>> _future = _load();

  Future<List<_Listed>> _load() async {
    final chats = await widget.repo.conversations();
    // One grouped query for the whole list rather than one per row.
    final latest = await context.read<MessageStore>().latestPerPeer();
    return [
      for (final chat in chats)
        (
          chat: chat,
          // The server's field is only ever a message *kind* now — "[image]"
          // for a conversation this device has no local copy of. Local text
          // wins over it, because local text is the actual message.
          preview: latest[chat.peerId.toString()]?.content ??
              chat.lastMessagePreview,
        ),
    ];
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: IronColors.gold,
      backgroundColor: IronColors.navySurface,
      onRefresh: _refresh,
      child: FutureBuilder<List<_Listed>>(
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
              chat: chats[i].chat,
              preview: chats[i].preview,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(
                    repo: widget.repo,
                    ws: widget.ws,
                    myId: widget.myId,
                    peerId: chats[i].chat.peerId,
                    peerName: chats[i].chat.peerName,
                    peerOnline: chats[i].chat.isOnline,
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
  const _ChatCard({
    required this.chat,
    required this.preview,
    required this.onTap,
  });

  final Conversation chat;

  /// Read from this device's decrypted history, not from the server. Null when
  /// the device has no local copy of the conversation yet — a fresh install,
  /// or a chat whose history has not been opened since.
  final String? preview;

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
                      preview ?? '…',
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
