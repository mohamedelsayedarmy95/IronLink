import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/env.dart';
import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../core/ws_service.dart';
import '../../../core/widgets/ticker.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/chat_bloc.dart';
import '../chat_repository.dart';
import '../widgets/attach_flow.dart';
import '../widgets/smart_replies.dart';
import '../widgets/summary_banner.dart';
import '../widgets/voice_player.dart';
import '../widgets/voice_recorder.dart';
import '../../../core/icons.dart';

class ChatRoomScreen extends StatelessWidget {
  const ChatRoomScreen({
    super.key,
    required this.repo,
    required this.ws,
    required this.myId,
    required this.peerId,
    required this.peerName,
    required this.peerOnline,
    required this.isSecret,
  });

  final ChatRepository repo;
  final WsService ws;
  final String myId;
  final String peerId;
  final String peerName;
  final bool peerOnline;
  final bool isSecret;

  @override
  Widget build(BuildContext context) {
    final baseUrl = Env.apiBaseUrl;
    final authToken = ''; // TODO: get from secure storage

    return BlocProvider(
      create: (_) => ChatBloc(
        repo: repo,
        ws: ws,
        myId: myId,
        peerId: peerId,
        isSecret: isSecret,
        baseUrl: baseUrl,
        authToken: authToken,
      )..add(const ChatOpened()),
      child: _ChatRoomView(
        peerName: peerName,
        peerOnline: peerOnline,
      ),
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
    final t = L.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: IronColors.navySurface,
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: IronColors.navyBorder),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: IronColors.navyDeep,
                border: Border.all(color: IronColors.navyBorder),
                boxShadow: widget.peerOnline
                    ? [
                        BoxShadow(
                          color: IronColors.gold.withValues(alpha: 0.25),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                widget.peerName.characters.first,
                style: const TextStyle(
                    color: IronColors.gold, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.peerName,
                    style: const TextStyle(
                        fontSize: 16, color: IronColors.textHi)),
                if (widget.peerOnline)
                  Text(t.onlineNow,
                      style: const TextStyle(
                          fontSize: 11, color: IronColors.gold)),
              ],
            ),
          ],
        ),
        actions: [
          // Secret chat toggle button (simplified)
          BlocBuilder<ChatBloc, ChatRoomState>(
            builder: (context, state) {
              return IconButton(
                tooltip: t.startSecretChat,
                icon: const Icon(IronIcons.lock, color: IronColors.gold),
                onPressed: () {
                  // In a full implementation, we would restart the bloc with isSecret=true
                  // For now, just show a snack bar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t.secretChatComingSoon),
                      backgroundColor: IronColors.gold,
                    ),
                  );
                },
              );
            },
          ),
          // AI Summary toggle (for demo, we'll just show it automatically if there are many messages)
          // In a real app, this could be a setting
        ],
      ),
      body: Column(
        children: [
          // News Ticker for OCR alerts
          const NewsTicker(),
          Expanded(
            child: BlocConsumer<ChatBloc, ChatRoomState>(
              listener: (_, __) => _jumpToBottom(),
              builder: (context, state) {
                if (state.loading) {
                  return const Center(
                      child: CircularProgressIndicator(color: IronColors.gold));
                }
                return Column(
                  children: [
                    // AI Summary Banner
                    if (state.summaryLoading)
                      SummaryBanner(
                        summary: '',
                        isLoading: true,
                        onRefresh: () {
                          context.read<ChatBloc>().add(ChatFetchSummaryStarted());
                        },
                      )
                    else if (state.summary.isNotEmpty)
                      SummaryBanner(
                        summary: state.summary,
                        isLoading: false,
                        onRefresh: () {
                          context.read<ChatBloc>().add(ChatFetchSummaryStarted());
                        },
                      )
                    else
                      const SizedBox.shrink(),

                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: state.messages.length,
                        itemBuilder: (context, i) {
                          final message = state.messages[i];
                          return _MessageBubble(
                            message: message,
                            onTranslatePressed: (text, targetLang) {
                              // Trigger translation for this message
                              // We need the message ID - we'll pass it via the message object
                              // For simplicity, we'll add a translate method to ChatBloc that takes messageId
                              // But we don't have access to messageId here easily
                              // Let's modify the approach: we'll add a method to the bloc state to translate
                              // For now, we'll just call the bloc event with the text and targetLang
                              // and assume we can get the messageId from somewhere
                              // This is a limitation - in a real implementation we'd pass messageId
                              context.read<ChatBloc>().add(ChatTranslateMessageStarted(
                                messageId: message.id,
                                text: text,
                                targetLang: targetLang,
                              ));
                            },
                            onModeratePressed: (text) {
                              context.read<ChatBloc>().add(ChatModerateMessageStarted(
                                messageId: message.id,
                                text: text,
                              ));
                            },
                          );
                        },
                      ),
                    ),

                    if (state.peerTyping)
                      _TypingIndicator(peerName: widget.peerName),

                    // Smart Replies
                    if (state.smartReplies.isNotEmpty && !state.smartRepliesLoading)
                      SmartReplies(
                        suggestions: state.smartReplies,
                        onTap: (suggestion) {
                          context.read<ChatBloc>().add(TextSent(suggestion));
                        },
                      ),

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
          ),
        ],
      ),
    );
  }
}

// ── Message bubble with translate/moderate callbacks ───────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.onTranslatePressed,
    required this.onModeratePressed,
  });

  final ChatMessage message;
  final void Function(String text, String targetLang) onTranslatePressed;
  final void Function(String text) onModeratePressed;

  static const _slateGrey = Color(0xFF3E4A5C);

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final mine = message.isMine;

    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        // Long-press for options (translate, moderate, unsend)
        onLongPress: mine && !message.deleted
            ? () => _showMessageOptions(context)
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
                    colors: [IronColors.goldBright, IronColors.gold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: mine
                ? (message.deleted ? IronColors.navySurface : null)
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(IronIcons.blocked, size: IronIcons.sizeCompact, color: IronColors.textLo),
                    const SizedBox(width: 6),
                    Text(t.messageDeleted,
                        style: const TextStyle(
                            color: IronColors.textLo,
                            fontStyle: FontStyle.italic,
                            fontSize: 13)),
                  ],
                )
              else
                if (message.kind == 'voice') ...[
                  VoicePlayer(
                    mediaKey: (jsonDecode(message.content ?? '{}') as Map<String, dynamic>)['mediaKey'] as String? ?? '',
                    duration: ((jsonDecode(message.content ?? '{}') as Map<String, dynamic>)['duration'] as num?)?.toDouble() ?? 0,
                    waveform: ((jsonDecode(message.content ?? '{}') as Map<String, dynamic>)['waveform'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
                  )
                ] else ...[
                  Text(
                    message.content ?? '',
                    style: TextStyle(
                      // Dark bold text on the bright cyan bubble for readability.
                      color: mine ? IronColors.navyDeep : IronColors.textHi,
                      fontWeight: mine ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 15,
                    ),
                  ),
                ],
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _time(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: mine
                          ? IronColors.navyDeep.withValues(alpha: 0.6)
                          : IronColors.textLo,
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

  void _showMessageOptions(BuildContext context) {
    final t = L.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: IronColors.navySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(IronIcons.translate, color: IronColors.gold),
              title: Text(t.translate),
              onTap: () {
                Navigator.pop(context);
                // For translation, we need to ask for target language
                // For simplicity, we'll use English as default
                final text = message.content ?? '';
                if (text.isNotEmpty) {
                  onTranslatePressed(text, 'eng_Latn'); // English
                }
              },
            ),
            ListTile(
              leading: const Icon(IronIcons.report, color: IronColors.gold),
              title: Text(t.reportMessage),
              onTap: () {
                Navigator.pop(context);
                final text = message.content ?? '';
                if (text.isNotEmpty) {
                  onModeratePressed(text);
                }
              },
            ),
            if (message.isMine && !message.deleted) ...[
              const Divider(color: IronColors.navyDeep),
              ListTile(
                leading: const Icon(IronIcons.delete,
                    color: IronColors.errorRed),
                title: Text(t.deleteForEveryone,
                    style: const TextStyle(color: IronColors.textHi)),
                subtitle: Text(t.deleteForEveryoneHint,
                    style: const TextStyle(color: IronColors.textLo, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  // Find the bloc and send unsend event
                  context.read<ChatBloc>().add(MessageUnsent(message.id));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ── One grey ����� ��� ��� � ��� � � ✓ (sent) → two grey ����� ��� ��� � ��� � � ✓��������������✓ (delivered) → two GOLD ����� ��� ��� � ��� � � ✓��������������✓ (read).
class _Ticks extends StatelessWidget {
  const _Ticks({required this.tick, required this.pending});

  final MessageTick tick;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final onBubble = IronColors.navyDeep;
    if (pending) {
      return Icon(IronIcons.pending, size: IronIcons.sizeCompact, color: onBubble.withValues(alpha: 0.6));
    }
    final read = tick == MessageTick.read;
    final double single = tick == MessageTick.sent ? 1 : 2;
    return Icon(
      single == 1 ? IronIcons.sent : IronIcons.delivered,
      size: 14,
      color: onBubble.withValues(alpha: read ? 0.85 : 0.6),
      shadows: read
          ? [Shadow(color: IronColors.goldBright.withValues(alpha: 0.5), blurRadius: 4)]
          : null,
    );
  }
}

// ── "typing…" indicator with 3 animated gold dots ─────────────────────────────
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
            L.of(context).typingIndicator(widget.peerName),
            style: const TextStyle(color: IronColors.gold, fontSize: 13),
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
                          color: IronColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        ]
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
    final bloc = context.read<ChatBloc>();
    final t = L.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: IronColors.navySurface,
          border: Border(top: BorderSide(color: IronColors.navyBorder)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: t.attach,
              icon: const Icon(IronIcons.attach, color: IronColors.gold),
              onPressed: () async {
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
                decoration: InputDecoration(
                  hintText: t.messageHint,
                  fillColor: IronColors.navyDeep,
                ),
              ),
            ),
            const SizedBox(width: 8),
            VoiceRecorder(
              onSend: (mediaKey, duration, waveform) => bloc.add(MediaSent(
                kind: 'voice',
                mediaKey: mediaKey,
                mimeType: 'audio/opus',
                caption: jsonEncode({
                  'mediaKey': mediaKey,
                  'duration': duration,
                  'waveform': waveform,
                }),
              )),
              onCancel: () {},
            ),
            CircleAvatar(
              backgroundColor: IronColors.gold,
              child: IconButton(
                tooltip: t.send,
                icon: const Icon(IronIcons.send,
                    color: IronColors.navyDeep, size: IronIcons.sizeInline),
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}