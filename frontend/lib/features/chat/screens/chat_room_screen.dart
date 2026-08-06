import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../core/ws_service.dart';
import '../bloc/chat_bloc.dart';
import '../chat_repository.dart';
import '../widgets/attach_flow.dart';
import '../widgets/voice_record_button.dart';

class ChatRoomScreen extends StatelessWidget {
  const ChatRoomScreen({
    super.key,
    required this.repo,
    required this.ws,
    required this.myId,
    required this.peerId,
    required this.peerName,
    required this.peerOnline,
  });

  final ChatRepository repo;
  final WsService ws;
  final String myId;
  final String peerId;
  final String peerName;
  final bool peerOnline;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatBloc(
        repo: repo,
        ws: ws,
        myId: myId,
        peerId: peerId,
      )..add(const ChatOpened()),
      child: _ChatRoomView(peerName: peerName, peerOnline: peerOnline),
    );
  }
}

class _ChatRoomView extends StatefulWidget {
  const _ChatRoomView({required this.peerName, required this.peerOnline});

  final String peerName;
  final bool peerOnline;

  @override
  State<_ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<_ChatRoomView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: MilColors.navySurface,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: MilColors.navyDeep,
              child: Text(
                widget.peerName.characters.first,
                style: const TextStyle(
                    color: MilColors.gold, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.peerName,
                    style: const TextStyle(
                        fontSize: 16, color: MilColors.textHi)),
                if (widget.peerOnline)
                  const Text('متصل الآن',
                      style: TextStyle(
                          fontSize: 11, color: MilColors.gold)),
              ],
            ),
          ],
        ),
      ),
      body: BlocConsumer<ChatBloc, ChatRoomState>(
        listener: (_, __) => _jumpToBottom(),
        builder: (context, state) {
          if (state.loading) {
            return const Center(
                child: CircularProgressIndicator(color: MilColors.gold));
          }
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) =>
                      _MessageBubble(message: state.messages[i]),
                ),
              ),
              if (state.peerTyping)
                _TypingIndicator(peerName: widget.peerName),
              _InputBar(
                controller: _input,
                onChanged: (text) => context
                    .read<ChatBloc>()
                    .add(TypingChanged(text.isNotEmpty)),
                onSend: () {
                  final text = _input.text.trim();
                  if (text.isEmpty) return;
                  context.read<ChatBloc>().add(TextSent(text));
                  _input.clear();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Message bubble: gold gradient (mine) / slate grey (theirs) ───────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  static const _slateGrey = Color(0xFF3E4A5C);

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;

    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        // Fable5-Enhancement: long-press on your own message opens the unsend
        // sheet — discoverable, and impossible to trigger by accident.
        onLongPress: mine && !message.deleted
            ? () => _showUnsendSheet(context)
            : null,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          margin: const EdgeInsets.only(bottom: 10),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: mine && !message.deleted
                ? const LinearGradient(
                    colors: [MilColors.goldBright, MilColors.gold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: mine
                ? (message.deleted ? MilColors.navySurface : null)
                : _slateGrey,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(16),
              topEnd: const Radius.circular(16),
              bottomStart: Radius.circular(mine ? 16 : 4),
              bottomEnd: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.deleted)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block, size: 14, color: MilColors.textLo),
                    SizedBox(width: 6),
                    Text('تم حذف هذه الرسالة',
                        style: TextStyle(
                            color: MilColors.textLo,
                            fontStyle: FontStyle.italic,
                            fontSize: 13)),
                  ],
                )
              else
                Text(
                  message.content ?? '',
                  style: TextStyle(
                    // Dark bold text on gold for readability, as specified
                    color: mine ? const Color(0xFF1A1503) : MilColors.textHi,
                    fontWeight: mine ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 15,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _time(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: mine
                          ? const Color(0x991A1503)
                          : MilColors.textLo,
                    ),
                  ),
                  if (mine && !message.deleted) ...[
                    const SizedBox(width: 5),
                    _Ticks(tick: message.tick, pending: message.pending),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnsendSheet(BuildContext context) {
    final bloc = context.read<ChatBloc>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MilColors.navySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_forever_outlined,
              color: MilColors.errorRed),
          title: const Text('حذف لدى الجميع',
              style: TextStyle(color: MilColors.textHi)),
          subtitle: const Text('متاح خلال 5 دقائق من الإرسال',
              style: TextStyle(color: MilColors.textLo, fontSize: 12)),
          onTap: () {
            bloc.add(MessageUnsent(message.id));
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// One grey ✓ (sent) → two grey ✓✓ (delivered) → two GOLD ✓✓ (read).
class _Ticks extends StatelessWidget {
  const _Ticks({required this.tick, required this.pending});

  final MessageTick tick;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    if (pending) {
      return const Icon(Icons.schedule,
          size: 13, color: Color(0x991A1503));
    }
    final gold = tick == MessageTick.read;
    final double single = tick == MessageTick.sent ? 1 : 2;
    final color = gold
        ? const Color(0xFF7A5C00) // deep gold — visible ON the gold bubble
        : const Color(0x991A1503);
    return Icon(
      single == 1 ? Icons.done : Icons.done_all,
      size: 14,
      color: gold ? const Color(0xFF5C4400) : color,
      shadows: gold
          ? const [Shadow(color: Color(0xFFFFE082), blurRadius: 4)]
          : null,
    );
  }
}

// ── "يكتب..." indicator with 3 animated gold dots ────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.peerName});

  final String peerName;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 20, bottom: 6),
      child: Row(
        children: [
          Text(
            '${widget.peerName} يكتب',
            style: const TextStyle(color: MilColors.gold, fontSize: 13),
          ),
          const SizedBox(width: 6),
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Opacity(
                      opacity: _dotOpacity(i),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: MilColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _dotOpacity(int i) {
    final phase = (_c.value + i * 0.2) % 1.0;
    return 0.25 + 0.75 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
  }
}

// ── Input bar: mic + attach sheet + send ─────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        color: MilColors.navySurface,
        child: Row(
          children: [
            IconButton(
              tooltip: 'إرفاق',
              icon: const Icon(Icons.attach_file, color: MilColors.gold),
              onPressed: () async {
                final bloc = context.read<ChatBloc>();
                final media = context.read<MediaService>();
                final result =
                    await showAttachFlow(context, media: media);
                if (result != null) {
                  bloc.add(MediaSent(
                    kind: 'image',
                    mediaKey: result.mediaKey,
                    mimeType: result.mimeType,
                    caption: result.caption,
                  ));
                }
              },
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالة…',
                  fillColor: MilColors.navyDeep,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Builder(builder: (context) {
              final bloc = context.read<ChatBloc>();
              return VoiceRecordButton(
                media: context.read<MediaService>(),
                onRecorded: (key, mime) => bloc.add(MediaSent(
                  kind: 'file',
                  mediaKey: key,
                  mimeType: mime,
                )),
              );
            }),
            CircleAvatar(
              backgroundColor: MilColors.gold,
              child: IconButton(
                tooltip: 'إرسال',
                icon: const Icon(Icons.send,
                    color: MilColors.navyDeep, size: 20),
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
