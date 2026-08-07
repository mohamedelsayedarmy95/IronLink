import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/env.dart';
import '../../../core/media_service.dart';
import '../../../core/theme.dart';
import '../../../core/ws_service.dart';
import '../../../core/widgets/ticker.dart';
import '../bloc/chat_bloc.dart';
import '../chat_repository.dart';
import '../widgets/attach_flow.dart';
import '../widgets/smart_replies.dart';
import '../widgets/summary_banner.dart';
import '../widgets/voice_player.dart';
import '../widgets/voice_recorder.dart';

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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: IronColors.navySurface,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: IronColors.navyDeep,
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
                  const Text('متصل الآن',
                      style: TextStyle(
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
                tooltip: 'بدء محادثة سرية',
                icon: const Icon(Icons.lock, color: IronColors.gold),
                onPressed: () {
                  // In a full implementation, we would restart the bloc with isSecret=true
                  // For now, just show a snack bar
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تفعيل المحادثة السرية (سيتم تطبيقها في التحديث التالي)'),
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
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block, size: 14, color: IronColors.textLo),
                    SizedBox(width: 6),
                    Text('تم حذف هذه الرسالة',
                        style: TextStyle(
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
                      // Dark bold text on gold for readability, as specified
                      color: mine ? const Color(0xFF1A1503) : IronColors.textHi,
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
                          ? const Color(0x991A1503)
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
              leading: const Icon(Icons.translate, color: IronColors.gold),
              title: const Text('ترجمة'),
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
              leading: const Icon(Icons.shield, color: IronColors.gold),
              title: const Text('إبلاغ عن رسالة'),
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
                leading: const Icon(Icons.delete_forever_outlined,
                    color: IronColors.errorRed),
                title: const Text('حذف لدى الجميع',
                    style: TextStyle(color: IronColors.textHi)),
                subtitle: const Text('متاح خلال 5 دقائق من الإرسال',
                    style: TextStyle(color: IronColors.textLo, fontSize: 12)),
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
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        color: IronColors.navySurface,
        child: Row(
          children: [
            IconButton(
              tooltip: 'إرفاق',
              icon: const Icon(Icons.attach_file, color: IronColors.gold),
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
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالة…',
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
                tooltip: 'إرسال',
                icon: const Icon(Icons.send,
                    color: IronColors.navyDeep, size: 20),
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}